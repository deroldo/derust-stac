import 'package:flutter/foundation.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

class _KeyNotifier extends ChangeNotifier implements ValueListenable<Object?> {
  _KeyNotifier(this._value);

  Object? _value;

  @override
  Object? get value => _value;

  /// Sets the value; returns whether listeners should be notified.
  bool set(Object? next) {
    if (next is! List && next is! Map && next == _value) return false;
    _value = next;
    return true;
  }

  void notify() => notifyListeners();
}

/// In-memory [StacStateStore].
class StacMemoryStateStore implements StacStateStore {
  StacMemoryStateStore();

  final Map<String, _KeyNotifier> _notifiers = {};
  final Map<String, Object?> _initials = {};
  final Set<String> _dirty = {};
  int _batchDepth = 0;

  @override
  bool has(String key) => _notifiers.containsKey(key);

  @override
  Object? read(String key) => _notifiers[key]?.value;

  @override
  ValueListenable<Object?>? listenable(String key) => _notifiers[key];

  @override
  void declare(String key, Object? initial) {
    if (stacReservedStateNames.contains(key)) {
      Log.e('State key "$key" is reserved and cannot be declared.');
      return;
    }
    if (_notifiers.containsKey(key)) return;
    final frozen = freezeStateValue(initial);
    _initials[key] = frozen;
    _notifiers[key] = _KeyNotifier(frozen);
  }

  @override
  bool write(String key, Object? value) {
    final notifier = _notifiers[key];
    if (notifier == null || stacReservedStateNames.contains(key)) {
      Log.e('Cannot write state key "$key": not declared or reserved.');
      return false;
    }
    _apply(key, notifier, freezeStateValue(value));
    return true;
  }

  void _apply(String key, _KeyNotifier notifier, Object? value) {
    if (!notifier.set(value)) return;
    if (_batchDepth > 0) {
      _dirty.add(key);
    } else {
      notifier.notify();
    }
  }

  @override
  void batch(void Function() body) {
    _batchDepth++;
    try {
      body();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0) _flush();
    }
  }

  void _flush() {
    final keys = _dirty.toList();
    _dirty.clear();
    for (final key in keys) {
      _notifiers[key]?.notify();
    }
  }

  @override
  void reset(String key) {
    final notifier = _notifiers[key];
    if (notifier == null) return;
    _apply(key, notifier, _initials[key]);
  }

  @override
  void resetAll() {
    batch(() {
      for (final key in _notifiers.keys.toList()) {
        reset(key);
      }
    });
  }

  @override
  Object? initialOf(String key) => _initials[key];

  @override
  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
    _notifiers.clear();
    _initials.clear();
    _dirty.clear();
  }

  /// Deep copy wrapped in unmodifiable collections.
  @visibleForTesting
  static Object? freeze(Object? value) => freezeStateValue(value);
}

/// Deep-copies [value], wrapping lists and maps as unmodifiable.
Object? freezeStateValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final e in value.entries)
        e.key.toString(): freezeStateValue(e.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(freezeStateValue));
  }
  return value;
}
