import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/framework/stac_network_view.dart';
import 'package:stac/src/recovery/stac_recovery_exception.dart';
import 'package:stac/src/recovery/stac_recovery_interceptor.dart';
import 'package:stac/stac.dart';

import '../state/harness.dart';

const _contentType = 'application/vnd.stac.error+json';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/recovery/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Response<dynamic> _response(
  Map<String, dynamic> body, {
  int status = 401,
  String type = _contentType,
}) => Response<dynamic>(
  requestOptions: RequestOptions(path: 'https://x.test/resource'),
  statusCode: status,
  data: body,
  headers: Headers.fromMap({
    Headers.contentTypeHeader: [type],
  }),
);

FakeResponse _asEnvelope(Map<String, dynamic> body, {int status = 401}) =>
    FakeResponse(
      body,
      statusCode: status,
      headers: {
        Headers.contentTypeHeader: [_contentType],
      },
    );

void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  setUpAll(() => initStacForTest(dio: dio));

  group('envelope fixtures: recognizer and models', () {
    test('marker + version', () {
      final envelope = StacEnvelopeRecognizer.recognize(
        _response(_fixture('envelope_marker_version')),
      );
      expect(envelope, isNotNull);
      expect(envelope!.version, 1);
      expect(envelope.recovery, isNull);
      expect(envelope.screen, isNull);
      expect(envelope.action, isNull);
    });

    test('full recovery', () {
      final envelope = StacEnvelopeRecognizer.recognize(
        _response(_fixture('envelope_recovery_full')),
      )!;
      expect(envelope.code, 'needs_recovery');
      final recovery = envelope.recovery!;
      expect(recovery.key, 'recovery-1');
      expect(recovery.recover, isA<List>());
      expect((recovery.recover as List), hasLength(2));
      expect(recovery.retry!.headers, {'X-Extra': 'e'});
      expect(recovery.retry!.removeHeaders, ['X-Plain']);
      expect(recovery.onFailure, isA<Map>());
      expect(recovery.onUnavailable, isA<List>());
      expect(recovery.timeoutMs, 5000);
    });

    test('screen only is a parseable widget', () {
      final envelope = StacEnvelopeRecognizer.recognize(
        _response(_fixture('envelope_screen_only'), status: 500),
      )!;
      expect(envelope.screen, isNotNull);
      expect(envelope.action, isNull);
      expect(envelope.recovery, isNull);
      final parser = StacRegistry.instance.getParser(
        envelope.screen!['type'] as String,
      );
      expect(parser, isNotNull);
    });

    test('action only is a parseable action', () {
      final envelope = StacEnvelopeRecognizer.recognize(
        _response(_fixture('envelope_action_only'), status: 500),
      )!;
      expect(envelope.action, isNotNull);
      expect(envelope.screen, isNull);
      expect(
        StacRegistry.instance.getActionParser(
          envelope.action!['actionType'] as String,
        ),
        isNotNull,
      );
    });

    test('unknown version is a regular error', () {
      expect(
        StacEnvelopeRecognizer.recognize(
          _response(_fixture('envelope_unknown_version')),
        ),
        isNull,
      );
    });

    test('same bodies are not envelopes without the marker or on 2xx', () {
      final body = _fixture('envelope_recovery_full');
      expect(
        StacEnvelopeRecognizer.recognize(
          _response(body, type: 'application/json'),
        ),
        isNull,
      );
      expect(
        StacEnvelopeRecognizer.recognize(_response(body, status: 200)),
        isNull,
      );
    });

    test('recoveryOutcome in the fixture is parsed by its action parser', () {
      final recover =
          (_fixture('envelope_recovery_full')['recovery']
                  as Map<String, dynamic>)['recover']
              as List;
      final json = Map<String, dynamic>.from(recover.last as Map);
      final parser = StacRegistry.instance.getActionParser(
        json['actionType'] as String,
      )!;
      final model = parser.getModel(json) as StacRecoveryOutcome;
      expect(model.result, StacRecoveryOutcomeResult.success);
    });
  });

  group('envelope fixtures: full cycle', () {
    late FakeResponse Function(RequestOptions) server;
    var recoverHits = 0;
    var recoverStatus = 200;

    setUp(() {
      adapter.requests.clear();
      recoverHits = 0;
      recoverStatus = 200;
      StacRecoveryInterceptor.instance.reset();
      server = (o) {
        if (o.uri.path == '/recover') {
          recoverHits++;
          return FakeResponse({'value': 'new'}, statusCode: recoverStatus);
        }
        if (o.headers['X-Ctx'] == 'new') {
          return const FakeResponse({'type': 'text', 'data': 'done'});
        }
        return _asEnvelope(_fixture('envelope_recovery_full'));
      };
      adapter.responder = (o) => server(o);
      final store = StacGlobalState.instance.store;
      for (final e in {'ctx': 'old', 'failed': 0, 'unavailable': 0}.entries) {
        store
          ..declare(e.key, e.value)
          ..write(e.key, e.value);
      }
    });

    Future<Object?> run(WidgetTester tester) async {
      await pumpStac(tester, {
        'type': 'column',
        'children': [
          {'type': 'text', 'data': 'host'},
        ],
      }, dio: dio);
      Object? result;
      var done = false;
      final context = tester.element(find.text('host'));
      final request = StacNetworkRequest(
        url: 'https://x.test/resource',
        method: Method.get,
        headers: {'X-Ctx': StacBinding.state('global.ctx'), 'X-Plain': 'p'},
      );
      StacNetworkLoad.start(context, request).future.then<void>(
        (r) {
          result = r;
          done = true;
        },
        onError: (Object e) {
          result = e;
          done = true;
        },
      );
      for (var t = 0; t < 600; t += 10) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done, isTrue, reason: 'the request never finished');
      return result;
    }

    Object? global(String key) => StacGlobalState.instance.store.read(key);

    testWidgets('error -> recover -> single repetition', (tester) async {
      await run(tester);
      expect(adapter.requests.map((r) => r.uri.path), [
        '/resource',
        '/recover',
        '/resource',
      ]);
      final first = adapter.requests.first;
      final second = adapter.requests.last;
      expect(first.headers['X-Ctx'], 'old');
      expect(second.headers['X-Ctx'], 'new');
      expect(second.headers['X-Extra'], 'e');
      expect(second.headers.containsKey('X-Plain'), isFalse);
      expect(second.uri, first.uri);
      expect(second.method, first.method);
      expect(recoverHits, 1);
      expect(global('ctx'), 'new');
      expect(global('failed'), 0);
      expect(global('unavailable'), 0);
    });

    testWidgets('failing recover ends in the final error and onFailure', (
      tester,
    ) async {
      recoverStatus = 403;
      // Without the explicit `recoveryOutcome`, the result is deduced from
      // the status of the request made by `recover` (4xx = failure).
      final body = _fixture('envelope_recovery_full');
      final recovery = body['recovery'] as Map<String, dynamic>;
      recovery['recover'] = [(recovery['recover'] as List).first];
      server = (o) {
        if (o.uri.path != '/recover') return _asEnvelope(body);
        recoverHits++;
        return FakeResponse({'value': 'x'}, statusCode: recoverStatus);
      };
      final result = await run(tester);
      expect(result, isA<StacRecoveryException>());
      expect(recoverHits, 1);
      expect(global('failed'), 1);
      expect(global('unavailable'), 0);
      expect(
        adapter.requests.where((r) => r.uri.path == '/resource'),
        hasLength(1),
        reason: 'no repetition after a failed recover',
      );
    });

    testWidgets('unknown version is not recovered', (tester) async {
      server = (o) => _asEnvelope(_fixture('envelope_unknown_version'));
      await run(tester);
      expect(adapter.requests.map((r) => r.uri.path), ['/resource']);
    });
  });
}
