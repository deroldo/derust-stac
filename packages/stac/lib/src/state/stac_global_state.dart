import 'package:flutter/foundation.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/src/state/stac_state_store.dart';

/// Process-wide state shared by every screen. Never disposed.
class StacGlobalState {
  StacGlobalState._();

  static final StacGlobalState instance = StacGlobalState._();

  StacStateStore _store = StacMemoryStateStore();

  StacStateStore get store => _store;

  /// Drops every key (tests only).
  @visibleForTesting
  void clear() {
    _store = StacMemoryStateStore();
  }
}
