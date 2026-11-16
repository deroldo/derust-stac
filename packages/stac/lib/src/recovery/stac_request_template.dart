import 'dart:async';

import 'package:dio/dio.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';
import 'package:stac_logger/stac_logger.dart';

/// `RequestOptions.extra` key holding the [StacRequestTemplate] of a request
/// made through `StacNetworkService.request`.
const String stacTemplateExtraKey = 'stac.template';

/// `RequestOptions.extra` key marking a request that must not be recovered
/// (the repetition itself, requests made by `recover`, `onFailure`, ...).
const String stacRecoveryExemptExtraKey = 'stac.recovery.exempt';

/// `RequestOptions.extra` key marking a request whose body cannot be sent
/// twice (a `Stream` or a `FormData`).
const String stacRetryUnsafeExtraKey = 'stac.retry.unsafe';

/// Whether the request this belongs to is still wanted: its `CancelToken` was
/// not cancelled and its screen is still alive.
typedef StacRequestAlive = bool Function();

/// What it takes to send a request again with its bindings re-evaluated: the
/// request JSON *before* `resolveBindings`, the scopes visible where it was
/// triggered, and the request's life.
///
/// Travels in `RequestOptions.extra[stacTemplateExtraKey]`. A request made
/// without a template (the app's own Dio) is repeated from its
/// `RequestOptions` instead.
class StacRequestTemplate {
  const StacRequestTemplate({
    required this.json,
    required this.scope,
    required this.alive,
    this.requestKey,
    this.cancelToken,
    this.stateBody = false,
  });

  /// `networkRequest` JSON with its bindings still unresolved.
  final Map<String, dynamic> json;

  /// Scopes captured where the request was triggered.
  final StacCapturedScope scope;

  /// See [StacRequestAlive]. Also see [isAlive].
  final StacRequestAlive alive;

  final String? requestKey;

  /// Token of the first attempt; the repetition reuses it, so cancelling the
  /// request (or closing its screen) also cancels the repetition.
  final CancelToken? cancelToken;

  /// Whether `bodyFromState` of [json] is applied to the body (a
  /// `networkRequest` action does; a request carried by `fromNetwork` does
  /// not).
  final bool stateBody;

  /// [alive] and the token not cancelled.
  bool get isAlive => !(cancelToken?.isCancelled ?? false) && alive();

  /// Template carried by [options], if any.
  static StacRequestTemplate? of(RequestOptions options) {
    final value = options.extra[stacTemplateExtraKey];
    return value is StacRequestTemplate ? value : null;
  }
}

/// Whether [options] must not be recovered.
bool stacRecoveryExempt(RequestOptions options) =>
    options.extra[stacRecoveryExemptExtraKey] == true;

/// Whether the body of [options] cannot be sent again (M9).
bool stacRetryUnsafe(RequestOptions options) =>
    options.extra[stacRetryUnsafeExtraKey] == true ||
    stacBodyIsUnreplayable(options.data);

/// `Stream` and `FormData` bodies are consumed by the first attempt.
bool stacBodyIsUnreplayable(Object? body) => body is Stream || body is FormData;

// -- recovery exemption by Zone (M3) -------------------------------------

/// Zone key of the recovery exemption. Read when the `RequestOptions` are
/// built (not in the interceptor) and copied to
/// `extra[stacRecoveryExemptExtraKey]`.
const Symbol stacRecoveryExemptZoneKey = #stacRecoveryExempt;

/// Whether the current zone is exempt from recovery.
bool get stacRecoveryExemptInZone =>
    Zone.current[stacRecoveryExemptZoneKey] == true;

/// Runs [fn] (and its async continuations) in a zone where every request it
/// builds is exempt from recovery.
Future<T> runExempt<T>(FutureOr<T> Function() fn) => runZoned(
  () async => await fn(),
  zoneValues: {stacRecoveryExemptZoneKey: true},
);

// -- unresolved request JSON handed to the networkRequest parser ----------

Map<String, dynamic>? _pendingUnresolvedRequest;

/// Runs [body] (the synchronous start of the `networkRequest` parser) with
/// [json], the action JSON before its bindings were resolved, available to
/// [takeStacUnresolvedRequest].
T runWithStacUnresolvedRequest<T>(
  Map<String, dynamic> json,
  T Function() body,
) {
  _pendingUnresolvedRequest = json;
  try {
    return body();
  } finally {
    _pendingUnresolvedRequest = null;
  }
}

/// The JSON handed by [runWithStacUnresolvedRequest], consumed (it is only
/// valid until the first `await` of the parser).
Map<String, dynamic>? takeStacUnresolvedRequest() {
  final json = _pendingUnresolvedRequest;
  _pendingUnresolvedRequest = null;
  return json;
}

// -- bodyFromState --------------------------------------------------------

/// `bodyFromState`: `{key: value}` of the listed keys, without `secure`
/// ones, evaluated now. An explicit `body` wins. [scope] is only built when
/// there is something to read.
StacNetworkRequest stacRequestWithStateBody(
  StacScope Function() scope,
  StacNetworkRequest model,
) {
  final keys = model.bodyFromState;
  if (keys == null || keys.isEmpty) return model;
  if (model.body != null) {
    Log.w(
      StacGlobalState.instance.redact(
        'networkRequest ${model.url}: both body and bodyFromState set; '
        'the explicit body wins',
      ),
    );
    return model;
  }
  final stacScope = scope();
  final body = <String, Object?>{};
  for (final key in keys) {
    final store = stacScope.storeFor(key);
    if (store != null && store.isSecure(stacStateLocalKey(key))) {
      Log.w('bodyFromState: "$key" is secure and was left out');
      continue;
    }
    body[key] = stacStateRead(stacScope, key);
  }
  return StacNetworkRequest(
    url: model.url,
    method: model.method,
    queryParameters: model.queryParameters,
    headers: model.headers,
    contentType: model.contentType,
    body: body,
    results: model.results,
    onStart: model.onStart,
    onSuccess: model.onSuccess,
    onError: model.onError,
    onFinally: model.onFinally,
    requestKey: model.requestKey,
    bodyFromState: model.bodyFromState,
  );
}

// -- retry overrides ------------------------------------------------------

/// Applies `retry.removeHeaders` and then `retry.overrides` to [json] (a
/// request JSON; the URL and the method are never touched).
///
/// `overrides` has `headers`, `queryParameters` and `body`. Maps are merged
/// by key, a `null` value removes the key (header names compare ignoring
/// case); a `null` section removes the whole section; a non-map `body`
/// replaces the body. Values are taken as they are, so bindings in them are
/// still unresolved.
Map<String, dynamic> stacApplyRetryOverrides(
  Map<String, dynamic> json, {
  Map<String, dynamic>? overrides,
  List<String>? removeHeaders,
}) {
  final result = Map<String, dynamic>.of(json);
  if (removeHeaders != null && removeHeaders.isNotEmpty) {
    final headers = result['headers'];
    if (headers is Map) {
      result['headers'] = {
        for (final e in headers.entries)
          if (!_containsIgnoreCase(removeHeaders, '${e.key}'))
            '${e.key}': e.value,
      };
    }
  }
  if (overrides == null) return result;
  for (final section in const ['headers', 'queryParameters', 'body']) {
    if (!overrides.containsKey(section)) continue;
    final override = overrides[section];
    if (override == null) {
      result.remove(section);
    } else if (override is Map) {
      final base = result[section];
      result[section] = mergeStacOverride(
        base is Map ? base : null,
        override,
        ignoreCase: section == 'headers',
      );
    } else if (section == 'body') {
      result[section] = override;
    } else {
      Log.w('retry.overrides.$section must be a map; ignored');
    }
  }
  return result;
}

/// [base] with [override] merged by key; a `null` value removes the key.
Map<String, dynamic> mergeStacOverride(
  Map<dynamic, dynamic>? base,
  Map<dynamic, dynamic> override, {
  bool ignoreCase = false,
}) {
  final merged = <String, dynamic>{
    if (base != null)
      for (final e in base.entries) '${e.key}': e.value,
  };
  for (final e in override.entries) {
    final key = '${e.key}';
    if (ignoreCase) {
      final lower = key.toLowerCase();
      merged.removeWhere((k, _) => k.toLowerCase() == lower);
    } else {
      merged.remove(key);
    }
    if (e.value != null) merged[key] = e.value;
  }
  return merged;
}

bool _containsIgnoreCase(List<String> names, String name) {
  final lower = name.toLowerCase();
  return names.any((n) => n.toLowerCase() == lower);
}
