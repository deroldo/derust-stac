import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

Response<dynamic> _res(
  dynamic data, {
  int status = 401,
  String? contentType = 'application/vnd.stac.error+json',
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: status,
    data: data,
    headers: Headers.fromMap({
      if (contentType != null) 'content-type': [contentType],
    }),
  );
}

Map<String, dynamic> _env({Object? version = 1}) => {
  'version': version,
  'code': 'SESSION_EXPIRED',
  'message': 'm',
  'recovery': {
    'recover': {'type': 'networkRequest'},
    'retry': {
      'overrides': {
        'headers': {'X': 'y', 'Z': null},
      },
      'removeHeaders': ['A'],
    },
    'onFailure': [
      {'type': 'navigate'},
    ],
    'timeoutMs': 5000,
  },
};

void main() {
  StacErrorEnvelope? run(Response<dynamic> r) =>
      StacEnvelopeRecognizer.recognize(r);

  test('marker ok', () {
    final e = run(_res(_env()))!;
    expect(e.version, 1);
    expect(e.code, 'SESSION_EXPIRED');
    final r = e.recovery!;
    expect(r.recover, isA<Map>());
    expect(r.onFailure, isA<List>());
    expect(r.timeoutMs, 5000);
    expect(r.retry!.headers, {'X': 'y', 'Z': null});
    expect(r.retry!.removeHeaders, ['A']);
  });

  test('envelope without recovery', () {
    final e = run(
      _res({
        'version': 1,
        'screen': {'type': 'text'},
      }),
    )!;
    expect(e.recovery, isNull);
    expect(e.screen, {'type': 'text'});
  });

  test('without marker', () {
    expect(run(_res(_env(), contentType: 'application/json')), isNull);
    expect(run(_res(_env(), contentType: null)), isNull);
  });

  test('content-type with charset and case', () {
    expect(
      run(
        _res(
          _env(),
          contentType: 'Application/Vnd.Stac.Error+json; charset=utf-8',
        ),
      ),
      isNotNull,
    );
  });

  test('version 2 / string version / missing', () {
    expect(run(_res(_env(version: 2))), isNull);
    expect(run(_res(_env(version: '1'))), isNull);
    expect(run(_res({'code': 'x'})), isNull);
  });

  test('invalid JSON string, valid JSON string, list body', () {
    expect(run(_res('{not json')), isNull);
    expect(run(_res(jsonEncode(_env()))), isNotNull);
    expect(run(_res([1, 2])), isNull);
    expect(run(_res(null)), isNull);
  });

  test('envelope in 2xx is ignored', () {
    expect(run(_res(_env(), status: 200)), isNull);
    expect(run(_res(_env(), status: 204)), isNull);
  });

  test('RFC 7807 body without marker', () {
    expect(
      run(
        _res({
          'type': 'about:blank',
          'title': 'x',
          'status': 401,
        }, contentType: 'application/problem+json'),
      ),
      isNull,
    );
  });

  test('any non-2xx status is accepted', () {
    for (final s in [400, 401, 403, 500, 503]) {
      expect(run(_res(_env(), status: s)), isNotNull, reason: '$s');
    }
  });

  test('malformed fields return null, never throw', () {
    expect(run(_res({'version': 1, 'recovery': 'x'})), isNull);
    expect(
      run(
        _res({
          'version': 1,
          'recovery': {'recover': 1},
        }),
      ),
      isNull,
    );
    expect(run(_res({'version': 1, 'code': 3})), isNull);
    expect(run(_res({'version': 1, 'screen': []})), isNull);
    expect(
      run(
        _res({
          'version': 1,
          'recovery': {'recover': [], 'timeoutMs': 'a'},
        }),
      ),
      isNull,
    );
    expect(run(_res(_env(), status: 0)), isNotNull);
    final noStatus = Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
    );
    expect(run(noStatus), isNull);
  });

  group('recovery.key', () {
    Map<String, dynamic> withKey(Map<String, dynamic> extra) => {
      'version': 1,
      'recovery': {'recover': <dynamic>[], ...extra},
    };

    test('absent', () {
      final r = run(_res(withKey({})))!.recovery!;
      expect(r.key, isNull);
      expect(r.keyDisabled, isFalse);
    });

    test('explicit null', () {
      final r = run(_res(withKey({'key': null})))!.recovery!;
      expect(r.key, isNull);
      expect(r.keyDisabled, isTrue);
    });

    test('string', () {
      final r = run(_res(withKey({'key': 'k'})))!.recovery!;
      expect(r.key, 'k');
      expect(r.keyDisabled, isFalse);
    });
  });
}
