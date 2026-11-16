import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/services/stac_network_service.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('concurrent requests keep their own headers and contentType', (
    tester,
  ) async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(headers: {'X-Default': 'd'}))
      ..httpClientAdapter = adapter;
    StacNetworkService.initialize(dio);

    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    // The POST awaits its body before reaching Dio; the GET starts in that gap.
    await tester.runAsync(() {
      final first = StacNetworkService.request(
        context,
        StacNetworkRequest(
          url: 'https://x.test/a',
          method: Method.post,
          headers: {'X-Id': 'one'},
          contentType: 'application/json',
          body: {'k': 'v'},
        ),
      );
      final second = StacNetworkService.request(
        context,
        StacNetworkRequest(
          url: 'https://x.test/b',
          method: Method.get,
          headers: {'X-Id': 'two'},
          contentType: 'text/plain',
        ),
      );
      return Future.wait([first, second]);
    });

    final a = adapter.requests.firstWhere((r) => r.path.endsWith('/a'));
    final b = adapter.requests.firstWhere((r) => r.path.endsWith('/b'));
    expect(a.headers['X-Id'], 'one');
    expect(a.contentType, 'application/json');
    expect(b.headers['X-Id'], 'two');
    expect(b.contentType, 'text/plain');
    // The app's Dio options are never mutated per request.
    expect(dio.options.headers['X-Id'], isNull);
    expect(dio.options.contentType, isNot('text/plain'));
  });
}
