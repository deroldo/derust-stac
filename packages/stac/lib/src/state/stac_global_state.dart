import 'package:flutter/foundation.dart';
import 'package:stac/src/state/stac_persistent_state_store.dart';
import 'package:stac/src/state/stac_state_persistence.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

/// Process-wide state shared by every screen. Never disposed.
class StacGlobalState {
  StacGlobalState._();

  static final StacGlobalState instance = StacGlobalState._();

  StacStateStore _store = StacPersistentStateStore();

  /// Placeholder shown instead of a `secure` value in logs and error output.
  static const String redacted = '***';

  StacStateStore get store => _store;

  static const Set<String> _declarationKeys = {'initial', 'persist', 'secure'};

  /// D14: loads the persisted keys (`persist`/`secure`) so they are available
  /// before the first screen is built. `Stac.initialize` awaits this. The
  /// storages default to `shared_preferences` and the platform secure
  /// storage (a no-op with a warning on web).
  Future<void> hydrate({
    StacStatePersistence? persistence,
    StacStatePersistence? securePersistence,
  }) async {
    final store = _store;
    if (store is! StacPersistentStateStore) return;
    store.configure(
      persistence: persistence ?? defaultStacPersistence(),
      securePersistence: securePersistence ?? defaultStacSecurePersistence(),
    );
    await store.hydrate();
  }

  /// Whether any `secure` key currently holds text worth redacting.
  bool get hasSecrets {
    final store = _store;
    return store is StacPersistentStateStore &&
        store.secretStrings().isNotEmpty;
  }

  /// Replaces every occurrence of a `secure` value's text in [text] by
  /// [redacted]. Use it on anything that may print state (logs, errors).
  String redact(String text) {
    final store = _store;
    if (store is! StacPersistentStateStore) return text;
    var result = text;
    for (final secret in store.secretStrings()) {
      result = result.replaceAll(secret, redacted);
    }
    return result;
  }

  /// Deep copy of [json] with [redact] applied to every text (keys and
  /// values). Returns [json] itself when there is nothing to hide.
  Object? redactJson(Object? json) {
    if (!hasSecrets) return json;
    if (json is String) return redact(json);
    if (json is Map) {
      return {
        for (final e in json.entries) redact('${e.key}'): redactJson(e.value),
      };
    }
    if (json is List) return [for (final v in json) redactJson(v)];
    return json;
  }

  /// D12: each value is either the initial value itself, or a declaration
  /// object (only `initial`/`persist`/`secure` keys, with `initial`).
  /// Idempotent: already declared keys keep their current value.
  void declareAll(Map<String, Object?> declarations) {
    declarations.forEach((key, value) {
      var initial = value;
      var flags = const StacKeyFlags();
      if (value is Map &&
          value.containsKey('initial') &&
          value.keys.every(_declarationKeys.contains)) {
        initial = value['initial'];
        final secure = value['secure'] == true;
        if (secure && value['persist'] == false) {
          Log.w(
            'globalState "$key": secure implies persist; persist: false '
            'ignored',
          );
        }
        flags = StacKeyFlags(
          persist: secure || value['persist'] == true,
          secure: secure,
        );
      }
      _store.declareWithFlags(key, initial, flags);
    });
  }

  /// Swaps the backing store (tests only), e.g. to stub `isSecure`.
  @visibleForTesting
  void useStore(StacStateStore store) {
    _store = store;
  }

  /// Drops every key (tests only).
  @visibleForTesting
  void clear() {
    _store = StacPersistentStateStore();
  }
}
