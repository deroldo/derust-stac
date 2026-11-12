import 'package:flutter/foundation.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

/// Process-wide state shared by every screen. Never disposed.
class StacGlobalState {
  StacGlobalState._();

  static final StacGlobalState instance = StacGlobalState._();

  StacStateStore _store = StacMemoryStateStore();

  StacStateStore get store => _store;

  static const Set<String> _declarationKeys = {'initial', 'persist', 'secure'};

  /// D12: each value is either the initial value itself, or a declaration
  /// object (only `initial`/`persist`/`secure` keys, with `initial`).
  /// Idempotent: already declared keys keep their current value.
  void declareAll(Map<String, Object?> declarations) {
    declarations.forEach((key, value) {
      var initial = value;
      if (value is Map &&
          value.containsKey('initial') &&
          value.keys.every(_declarationKeys.contains)) {
        initial = value['initial'];
        if (value['secure'] == true && value['persist'] == false) {
          Log.w(
            'globalState "$key": secure implies persist; persist: false '
            'ignored',
          );
        }
      }
      _store.declare(key, initial);
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
    _store = StacMemoryStateStore();
  }
}
