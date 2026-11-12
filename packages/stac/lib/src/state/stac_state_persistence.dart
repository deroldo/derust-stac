import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stac_logger/stac_logger.dart';

/// Prefix of every persisted state key (keeps Stac entries apart from the
/// app's own preferences).
const String stacStatePersistencePrefix = 'stac_state.';

/// Durable key/value storage for global state. Values are JSON strings; keys
/// are the state key names (the prefix is an implementation detail).
abstract class StacStatePersistence {
  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// `shared_preferences`-backed persistence for `persist: true` keys.
class SharedPrefsPersistence implements StacStatePersistence {
  const SharedPrefsPersistence();

  @override
  Future<Map<String, String>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final raw in prefs.getKeys()) {
      if (!raw.startsWith(stacStatePersistencePrefix)) continue;
      final value = prefs.get(raw);
      if (value is String) {
        result[raw.substring(stacStatePersistencePrefix.length)] = value;
      }
    }
    return result;
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$stacStatePersistencePrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$stacStatePersistencePrefix$key');
  }
}

/// Keychain / Keystore-backed persistence for `secure: true` keys.
class SecurePersistence implements StacStatePersistence {
  const SecurePersistence([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, String>> readAll() async {
    final all = await _storage.readAll();
    return {
      for (final e in all.entries)
        if (e.key.startsWith(stacStatePersistencePrefix))
          e.key.substring(stacStatePersistencePrefix.length): e.value,
    };
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$stacStatePersistencePrefix$key', value: value);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: '$stacStatePersistencePrefix$key');
}

/// Used where no secure storage is available (web): never stores anything.
class NoopSecurePersistence implements StacStatePersistence {
  const NoopSecurePersistence();

  static bool _warned = false;

  void _warn() {
    if (_warned) return;
    _warned = true;
    Log.w(
      'Secure storage is not available on this platform: "secure" global '
      'state keys are kept in memory only and are not persisted.',
    );
  }

  @override
  Future<Map<String, String>> readAll() async => const {};

  @override
  Future<void> write(String key, String value) async => _warn();

  @override
  Future<void> delete(String key) async {}

  @visibleForTesting
  static void resetWarning() => _warned = false;
}

/// Default persistence for non-secure keys.
StacStatePersistence defaultStacPersistence() => const SharedPrefsPersistence();

/// Default persistence for secure keys: the platform secure storage, or a
/// no-op (with a warning) on web.
StacStatePersistence defaultStacSecurePersistence() =>
    kIsWeb ? const NoopSecurePersistence() : const SecurePersistence();
