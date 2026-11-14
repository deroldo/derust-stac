@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
// The web plugin is registered by an app's generated registrant, which does not
// exist in `flutter test`, so it is registered by hand here.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/stac_persistent_state_store.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Runs only in a browser (`flutter test --platform chrome`): it exercises the
/// real `flutter_secure_storage` web implementation (WebCrypto + localStorage).
/// `localhost` counts as a secure context, so no HTTPS is needed here.

class _Recording implements StacStatePersistence {
  final Map<String, String> data = {};

  @override
  Future<Map<String, String>> readAll() async => {...data};

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

JSObject get _localStorage =>
    globalContext.getProperty<JSObject>('localStorage'.toJS);

String? _raw(String key) =>
    _localStorage.callMethod<JSString?>('getItem'.toJS, key.toJS)?.toDart;

StacPersistentStateStore get _global =>
    StacGlobalState.instance.store as StacPersistentStateStore;

Map<String, Object?> _secure(Object? initial) => {
  'initial': initial,
  'secure': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();

  setUp(() async {
    await initStacForTest();
    _localStorage.callMethod<JSAny?>('clear'.toJS);
    StacGlobalState.instance.clear();
  });

  test('runs on the web', () => expect(kIsWeb, isTrue));

  test(
    'a secureStatePersistence passed by the app wins over the web no-op',
    () async {
      final secure = _Recording();
      await StacGlobalState.instance.hydrate(
        persistence: _Recording(),
        securePersistence: secure,
      );
      StacGlobalState.instance.declareAll({'refreshToken': _secure('')});
      _global.write('refreshToken', 'rt-1');
      await _global.flush();
      expect(secure.data, {'refreshToken': jsonEncode('rt-1')});
    },
  );

  test('SecurePersistence keeps a secure key across an app restart', () async {
    await StacGlobalState.instance.hydrate(
      persistence: _Recording(),
      securePersistence: const SecurePersistence(),
    );
    StacGlobalState.instance.declareAll({'refreshToken': _secure('')});
    _global.write('refreshToken', 'rt-secret-123');
    await _global.flush();

    // Stored encrypted: the value is not readable in localStorage.
    final raw = _raw('FlutterSecureStorage.stac_state.refreshToken');
    expect(raw, isNotNull);
    expect(raw, isNot(contains('rt-secret-123')));

    // "Restart": a fresh store and a fresh storage instance, same localStorage.
    StacGlobalState.instance.clear();
    await StacGlobalState.instance.hydrate(
      persistence: _Recording(),
      securePersistence: const SecurePersistence(),
    );
    StacGlobalState.instance.declareAll({'refreshToken': _secure('')});
    expect(_global.read('refreshToken'), 'rt-secret-123');
  });
}
