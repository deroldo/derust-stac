import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/recovery/stac_recovery_interceptor.dart';
import 'package:stac/src/recovery/stac_recovery_run.dart';
import 'package:stac/src/recovery/stac_request_template.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';
import 'package:stac_logger/stac_logger.dart';

class StacNetworkService {
  const StacNetworkService._();

  static late Dio _dio;

  static Dio? _installedOn;

  /// Uses [dio] for every request and installs the recovery interceptor on it
  /// (once: initializing again with the same Dio does not duplicate it).
  static void initialize(Dio dio) {
    _dio = dio;
    final previous = _installedOn;
    if (previous != null && !identical(previous, dio)) {
      previous.interceptors.remove(StacRecoveryInterceptor.instance);
    }
    if (!dio.interceptors.any((i) => i is StacRecoveryInterceptor)) {
      dio.interceptors.add(StacRecoveryInterceptor.instance);
    }
    _installedOn = dio;
  }

  /// Resolves the `{"$state": ...}` / `{"$expr": ...}` bindings that sit in
  /// the data keys of [request] (`headers`, `body`, `queryParameters`, ...)
  /// against the scope of [context].
  ///
  /// A `networkRequest` action resolves its own JSON when it runs, but a
  /// request that is only *carried* by something else (`navigate`,
  /// `showDialog`, `showModalBottomSheet`, `networkWidget`, `dynamicView`) is a
  /// nested action/model that the binding walk deliberately skips, and it
  /// would reach the network with the raw binding maps (Dio turns a header
  /// map into the text `{$state: x}`). Those callers resolve it here, once,
  /// right before the request starts. Do not use it on a request that was
  /// already resolved: a value that happens to look like a binding would be
  /// resolved twice.
  static StacNetworkRequest resolveBindings(
    BuildContext context,
    StacNetworkRequest request,
  ) {
    if (!context.mounted) return request;
    final json = request.toJson();
    if (!StacBinding.hasBindings(json, isAction: true)) return request;
    final resolved = StacBinding.resolve(
      json,
      StacScope.of(context),
      isAction: true,
    );
    if (resolved is! Map<String, dynamic>) return request;
    return StacNetworkRequest.fromJson(resolved);
  }

  /// Sends [request]. [template], when given, is kept in
  /// `RequestOptions.extra[stacTemplateExtraKey]` so the request can be sent
  /// again with its bindings re-evaluated (see [retryRequest]).
  static Future<Response?> request(
    BuildContext context,
    StacNetworkRequest request, {
    CancelToken? cancelToken,
    StacRequestTemplate? template,
  }) async {
    switch (request.method) {
      case Method.get:
        return getRequest(
          request,
          cancelToken: cancelToken,
          template: template,
        );
      case Method.post:
        return postRequest(
          request,
          context.mounted ? context : context,
          cancelToken: cancelToken,
          template: template,
        );
      case Method.put:
        return putRequest(
          request,
          cancelToken: cancelToken,
          template: template,
        );
      case Method.delete:
        return deleteRequest(
          request,
          cancelToken: cancelToken,
          template: template,
        );
    }
  }

  /// Sends the request of [template] again, once: its bindings are evaluated
  /// again in the scope captured when it was triggered (so a value changed by
  /// a recovery is seen), then [removeHeaders] and [overrides] are applied
  /// (see [stacApplyRetryOverrides]; override values may hold bindings, which
  /// are resolved here). URL and method never change; the same `CancelToken`
  /// is used and the request is marked exempt from recovery. `onStart` is not
  /// run again (it belongs to the caller, not to the request).
  ///
  /// Throws the `DioException` of the repetition. Check [stacRetryUnsafe]
  /// first: a body that cannot be sent twice is refused here.
  static Future<Response?> retryTemplate(
    StacRequestTemplate template, {
    Map<String, dynamic>? overrides,
    List<String>? removeHeaders,
  }) {
    final json = Map<String, dynamic>.of(template.json)..remove('condition');
    final changed = stacApplyRetryOverrides(
      json,
      overrides: overrides,
      removeHeaders: removeHeaders,
    );
    final scope = template.scope;
    // Bindings are resolved when the repetition starts, in the captured
    // scope, inside the same chain context the first attempt ran in.
    return runWithStacCapturedScope<Response?>(
      scope,
      () => runExempt<Response?>(() {
        final resolved = StacBinding.hasBindings(changed, isAction: true)
            ? StacBinding.resolve(changed, scope.scope, isAction: true)
            : changed;
        var next = StacNetworkRequest.fromJson(
          Map<String, dynamic>.from(resolved as Map),
        );
        if (template.stateBody) {
          next = stacRequestWithStateBody(() => scope.scope, next);
        }
        if (stacBodyIsUnreplayable(next.body)) {
          throw _unsafe(null);
        }
        return request(
          scope.origin,
          next,
          cancelToken: template.cancelToken,
          template: template,
        );
      }),
    );
  }

  /// Sends the request that produced [options] again, once, going through the
  /// Dio interceptors like any request.
  ///
  /// With a template in `extra` this is [retryTemplate]. Without one (the
  /// app's own Dio) the original `RequestOptions` are repeated with the
  /// overrides applied; their values are used as they are (no scope to
  /// resolve bindings in). The same `CancelToken` is used and the request is
  /// marked exempt from recovery.
  static Future<Response?> retryRequest(
    RequestOptions options, {
    Map<String, dynamic>? overrides,
    List<String>? removeHeaders,
  }) {
    if (stacRetryUnsafe(options)) {
      return Future<Response?>.error(_unsafe(options));
    }
    final template = StacRequestTemplate.of(options);
    if (template != null) {
      return retryTemplate(
        template,
        overrides: overrides,
        removeHeaders: removeHeaders,
      );
    }
    final changed = stacApplyRetryOverrides(
      {
        'headers': Map<String, dynamic>.of(options.headers),
        'queryParameters': Map<String, dynamic>.of(options.queryParameters),
        if (options.data != null) 'body': options.data,
      },
      overrides: overrides,
      removeHeaders: removeHeaders,
    );
    final headers = changed['headers'];
    final query = changed['queryParameters'];
    final repeated = options.copyWith(
      headers: headers is Map ? Map<String, dynamic>.from(headers) : {},
      queryParameters: query is Map ? Map<String, dynamic>.from(query) : {},
      extra: {...options.extra, stacRecoveryExemptExtraKey: true},
    )..data = changed['body'];
    return _dio.fetch<dynamic>(repeated);
  }

  static DioException _unsafe(RequestOptions? options) {
    Log.w(
      'Request is not repeated: its body (stream/form data) cannot be sent '
      'twice',
    );
    return DioException(
      requestOptions: options ?? RequestOptions(),
      type: DioExceptionType.unknown,
      error: 'The request body cannot be sent twice',
    );
  }

  /// Headers and content type travel with each call. Writing them to the
  /// shared `_dio.options` would let a concurrent request overwrite them
  /// while this one awaits (e.g. the async POST body).
  ///
  /// The template, the recovery exemption (read from the current `Zone`, M3)
  /// and the "body cannot be sent twice" mark travel the same way, in `extra`;
  /// a plain request has none of them.
  static Options _optionsFor(
    StacNetworkRequest request, {
    StacRequestTemplate? template,
  }) {
    final direct = StacRecoveryRun.currentDirect;
    final extra = <String, dynamic>{
      stacTemplateExtraKey: ?template,
      stacRecoveryRunExtraKey: ?direct,
      if (stacRecoveryExemptInZone) stacRecoveryExemptExtraKey: true,
      if (stacBodyIsUnreplayable(request.body)) stacRetryUnsafeExtraKey: true,
    };
    return Options(
      headers: Map<String, dynamic>.from(request.headers ?? {}),
      contentType: request.contentType,
      extra: extra.isEmpty ? null : extra,
    );
  }

  static Future<Response?> getRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
    StacRequestTemplate? template,
  }) async {
    return _dio.get(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
      options: _optionsFor(request, template: template),
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> postRequest(
    StacNetworkRequest request,
    BuildContext context, {
    CancelToken? cancelToken,
    StacRequestTemplate? template,
  }) async {
    final body = await _updateBody(context, request.body);

    return _dio.post(
      request.url,
      data: body,
      queryParameters: request.queryParameters,
      options: _optionsFor(request, template: template),
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> putRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
    StacRequestTemplate? template,
  }) async {
    return _dio.put(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
      options: _optionsFor(request, template: template),
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> deleteRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
    StacRequestTemplate? template,
  }) async {
    return _dio.delete(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
      options: _optionsFor(request, template: template),
      cancelToken: cancelToken,
    );
  }

  static Future<dynamic> _updateBody(BuildContext context, dynamic body) async {
    // Lists (and other non-map JSON) go out untouched; only a missing body
    // keeps the legacy empty map.
    if (body != null && body is! Map) return body;

    Map<dynamic, dynamic> bodyMap = {};

    if (body is Map) {
      bodyMap.addAll(body);
      for (dynamic mapEntry in bodyMap.entries) {
        final key = mapEntry.key;
        final value = mapEntry.value;
        if (value is Map && value.containsKey('actionType')) {
          final dynamic callbackValue = await Future<dynamic>.value(
            Stac.onCallFromJson(value as Map<String, dynamic>, context),
          );
          bodyMap[key] = callbackValue;
        }
      }
    }

    return bodyMap;
  }
}
