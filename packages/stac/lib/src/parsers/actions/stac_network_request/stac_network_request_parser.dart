import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/services/stac_network_service.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';
import 'package:stac_logger/stac_logger.dart';

class StacNetworkRequestParser extends StacActionParser<StacNetworkRequest> {
  const StacNetworkRequestParser();

  @override
  String get actionType => ActionType.networkRequest.name;

  @override
  StacNetworkRequest getModel(Map<String, dynamic> json) =>
      StacNetworkRequest.fromJson(json);

  @override
  FutureOr onCall(BuildContext context, StacNetworkRequest model) async {
    // Everything up to the first await runs synchronously at trigger time:
    // the previous request with the same key is cancelled right here, so
    // calls are ordered by trigger, not by arrival of the responses.
    final registry = StacStateScope.requestsOf(context);
    final key = model.requestKey;
    final token = key == null ? registry.beginAnonymous() : registry.begin(key);
    try {
      return await _run(context, _withStateBody(context, model), token);
    } finally {
      registry.finish(key, token);
    }
  }

  Future<dynamic> _run(
    BuildContext context,
    StacNetworkRequest model,
    CancelToken token,
  ) async {
    // A request is discarded (no callback runs) once it was superseded or
    // cancelled, or when its screen/widget is gone. Checked after every await
    // so a late response never writes over newer state.
    bool alive() => !token.isCancelled && context.mounted;

    if (!await _runActions(context, model.onStart, alive)) return null;
    if (!context.mounted) return null;

    Response<dynamic>? response;
    try {
      response = await StacNetworkService.request(
        context,
        model,
        cancelToken: token,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return null;
      response = e.response;
      Log.e(StacGlobalState.instance.redact('${e.response ?? e}'));
    } catch (e) {
      Log.e(
        StacGlobalState.instance.redact(
          'networkRequest ${model.url} failed: $e',
        ),
      );
    }
    if (!alive()) return null;

    final statusCode = response?.statusCode;
    final succeeded = statusCode != null && statusCode ~/ 100 == 2;

    return runWithStacActionVars<dynamic>(
      {'response': _responseVars(response)},
      () async {
        if (!await _runActions(
          context,
          succeeded ? model.onSuccess : model.onError,
          alive,
        )) {
          return null;
        }
        if (!context.mounted) return null;
        if (!await _runActions(context, model.onFinally, alive)) return null;
        if (!context.mounted) return null;
        return _runLegacyResult(context, model, response, alive);
      },
    );
  }

  /// Legacy `results[statusCode]` + `{{response.x}}`, kept as is.
  Future<dynamic> _runLegacyResult(
    BuildContext context,
    StacNetworkRequest model,
    Response<dynamic>? response,
    bool Function() alive,
  ) async {
    final statusCode = response?.statusCode;
    if (statusCode == null) {
      return null;
    }

    final result = model.results
        .where((element) => element.statusCode == statusCode)
        .firstOrNull;
    if (result == null) {
      if (model.results.isNotEmpty) {
        Log.w('No networkRequest result for status $statusCode: ${model.url}');
      }
      return null;
    }

    if (alive()) {
      return Stac.onCallFromJson(
        _resolveResponse(result.action, response?.data),
        context,
      );
    }
  }

  /// Runs one action or a list of actions in sequence, awaiting each. Returns
  /// `false` as soon as the request is no longer [alive] (the rest is
  /// dropped).
  Future<bool> _runActions(
    BuildContext context,
    Object? actions,
    bool Function() alive,
  ) async {
    if (!alive()) return false;
    if (actions == null) return true;
    final list = actions is List ? actions : [actions];
    for (final action in list) {
      if (action is! Map) {
        Log.e(
          StacGlobalState.instance.redact(
            'networkRequest callback expects actions, got $action',
          ),
        );
        continue;
      }
      await Stac.onCallFromJson(Map<String, dynamic>.from(action), context);
      if (!alive()) return false;
    }
    return true;
  }

  /// `response` as seen by bindings: `{body, statusCode, headers}`.
  static Map<String, Object?> _responseVars(Response<dynamic>? response) {
    Object? body = response?.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        // Not JSON: keep the text.
      }
    }
    return {
      'body': body,
      'statusCode': response?.statusCode,
      'headers': {
        for (final e
            in response?.headers.map.entries ??
                const <MapEntry<String, List<String>>>[])
          e.key: e.value,
      },
    };
  }

  /// `bodyFromState`: `{key: value}` of the listed keys, without `secure`
  /// ones, evaluated now (at trigger time). An explicit `body` wins.
  StacNetworkRequest _withStateBody(
    BuildContext context,
    StacNetworkRequest model,
  ) {
    final keys = model.bodyFromState;
    if (keys == null || keys.isEmpty) return model;
    if (model.body != null) {
      Log.w(
        'networkRequest ${model.url}: both body and bodyFromState set; '
        'the explicit body wins',
      );
      return model;
    }
    final scope = StacScope.of(context);
    final body = <String, Object?>{};
    for (final key in keys) {
      final store = scope.storeFor(key);
      if (store != null && store.isSecure(stacStateLocalKey(key))) {
        Log.w('bodyFromState: "$key" is secure and was left out');
        continue;
      }
      body[key] = stacStateRead(scope, key);
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

  /// Matches `{{response}}` and `{{response.<path>}}`, where the path uses dot
  /// notation and list indexes, e.g. `{{response.items[0].id}}`.
  static final _responsePlaceholder = RegExp(
    r'\{\{\s*response((?:\.[^\s.\[\]{}]+|\[\d+\])*)\s*\}\}',
  );

  static const _notFound = Object();

  /// Fills `{{response}}` placeholders in [json] from the response body.
  ///
  /// A string that is only a placeholder takes the value as is (a map, list,
  /// number, ...); a placeholder inside longer text is inserted as text.
  /// Placeholders whose path isn't in the body are left unchanged, and so are
  /// the `results` of a nested `networkRequest`, which belong to its own
  /// response.
  dynamic _resolveResponse(dynamic json, dynamic data) {
    if (json is String) {
      final whole = _responsePlaceholder.matchAsPrefix(json);
      if (whole != null && whole.end == json.length) {
        final value = _valueAtPath(data, whole.group(1)!);
        return identical(value, _notFound) ? json : value;
      }
      return json.replaceAllMapped(_responsePlaceholder, (match) {
        final value = _valueAtPath(data, match.group(1)!);
        if (identical(value, _notFound)) return match.group(0)!;
        return value is Map || value is List ? jsonEncode(value) : '$value';
      });
    } else if (json is Map<String, dynamic>) {
      final isNestedRequest = json['actionType'] == actionType;
      return json.map(
        (key, value) => MapEntry(
          key,
          isNestedRequest && key == 'results'
              ? value
              : _resolveResponse(value, data),
        ),
      );
    } else if (json is List) {
      return json.map((item) => _resolveResponse(item, data)).toList();
    }
    return json;
  }

  dynamic _valueAtPath(dynamic data, String path) {
    final keys = path
        .replaceAllMapped(RegExp(r'\[(\d+)\]'), (match) => '.${match[1]}')
        .split('.')
        .where((key) => key.isNotEmpty);

    dynamic current = data;
    for (final key in keys) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else if (current is List) {
        final index = int.tryParse(key);
        if (index == null || index < 0 || index >= current.length) {
          return _notFound;
        }
        current = current[index];
      } else {
        return _notFound;
      }
    }
    return current;
  }
}
