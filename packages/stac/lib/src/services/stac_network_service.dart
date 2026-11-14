import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';

class StacNetworkService {
  const StacNetworkService._();

  static late Dio _dio;

  static void initialize(Dio dio) => _dio = dio;

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

  static Future<Response?> request(
    BuildContext context,
    StacNetworkRequest request, {
    CancelToken? cancelToken,
  }) async {
    Map<String, dynamic> headers = Map<String, dynamic>.from(
      request.headers ?? {},
    );
    _dio.options.headers = headers;
    _dio.options.contentType = request.contentType;

    switch (request.method) {
      case Method.get:
        return getRequest(request, cancelToken: cancelToken);
      case Method.post:
        return postRequest(
          request,
          context.mounted ? context : context,
          cancelToken: cancelToken,
        );
      case Method.put:
        return putRequest(request, cancelToken: cancelToken);
      case Method.delete:
        return deleteRequest(request, cancelToken: cancelToken);
    }
  }

  static Future<Response?> getRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
  }) async {
    return _dio.get(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> postRequest(
    StacNetworkRequest request,
    BuildContext context, {
    CancelToken? cancelToken,
  }) async {
    final body = await _updateBody(context, request.body);

    return _dio.post(
      request.url,
      data: body,
      queryParameters: request.queryParameters,
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> putRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
  }) async {
    return _dio.put(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
      cancelToken: cancelToken,
    );
  }

  static Future<Response?> deleteRequest(
    StacNetworkRequest request, {
    CancelToken? cancelToken,
  }) async {
    return _dio.delete(
      request.url,
      data: request.body,
      queryParameters: request.queryParameters,
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
