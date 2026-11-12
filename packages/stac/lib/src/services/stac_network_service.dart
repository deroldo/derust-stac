import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';

class StacNetworkService {
  const StacNetworkService._();

  static late Dio _dio;

  static void initialize(Dio dio) => _dio = dio;

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
