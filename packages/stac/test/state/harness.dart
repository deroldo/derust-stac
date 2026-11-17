import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

/// Queued response for [FakeDioAdapter].
class FakeResponse {
  const FakeResponse(
    this.body, {
    this.statusCode = 200,
    this.delay = Duration.zero,
    this.headers,
  });

  final Object? body;
  final int statusCode;
  final Duration delay;

  /// Response headers; defaults to `content-type: application/json`. A
  /// `content-type` given here replaces the default one.
  final Map<String, List<String>>? headers;
}

/// [HttpClientAdapter] serving queued responses in order, with optional delay.
class FakeDioAdapter implements HttpClientAdapter {
  final List<FakeResponse> _queue = [];
  final List<RequestOptions> requests = [];

  /// When set, answers every request instead of the queue.
  FakeResponse Function(RequestOptions options)? responder;

  void enqueue(FakeResponse response) => _queue.add(response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final FakeResponse response;
    if (responder != null) {
      response = responder!(options);
    } else {
      if (_queue.isEmpty) {
        throw StateError('FakeDioAdapter: no queued response');
      }
      response = _queue.removeAt(0);
    }
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
    final bytes = utf8.encode(jsonEncode(response.body));
    return ResponseBody.fromBytes(
      bytes,
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...?response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Persistence that stores nothing (the platform storages cannot run inside
/// `testWidgets`, where real asynchrony never completes).
class NullStatePersistence implements StacStatePersistence {
  const NullStatePersistence();

  @override
  Future<Map<String, String>> readAll() async => const {};

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

bool _initialized = false;

/// Initializes [StacService] once per test isolate.
Future<void> initStacForTest({Dio? dio}) async {
  if (_initialized) return;
  _initialized = true;
  await StacService.initialize(
    dio: dio ?? Dio(),
    statePersistence: const NullStatePersistence(),
    secureStatePersistence: const NullStatePersistence(),
  );
}

/// Renders [json] through `StacService.fromJson` inside a MaterialApp.
Future<void> pumpStac(
  WidgetTester tester,
  Map<String, dynamic> json, {
  Dio? dio,
}) async {
  await initStacForTest(dio: dio);
  await pumpStacWidget(
    tester,
    Builder(builder: (context) => StacService.fromJson(json, context)!),
  );
}

/// Pumps an arbitrary widget in a MaterialApp + Scaffold.
Future<void> pumpStacWidget(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}
