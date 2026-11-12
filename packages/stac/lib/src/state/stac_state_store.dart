import 'package:flutter/foundation.dart';

/// Names that cannot be used as screen state keys.
const Set<String> stacReservedStateNames = {
  'global',
  'params',
  'result',
  'response',
  'event',
};

/// Flags a key may carry (extension point for persistence, not used yet).
class StacKeyFlags {
  const StacKeyFlags({this.persist = false, this.secure = false});

  final bool persist;
  final bool secure;
}

/// Reactive key/value store backing screen and global state.
abstract class StacStateStore {
  bool has(String key);

  /// Reads a top-level key; absent keys read as `null`.
  Object? read(String key);

  /// Listenable for a declared key, `null` if the key is not declared.
  ValueListenable<Object?>? listenable(String key);

  /// Idempotent: if the key already exists, the current value is kept.
  void declare(String key, Object? initial);

  /// Writes an immutable deep copy. Returns `false` (and logs) if the key is
  /// not declared or is reserved.
  bool write(String key, Object? value);

  /// Defers notifications until the outermost [body] finishes.
  void batch(void Function() body);

  void reset(String key);

  void resetAll();

  Object? initialOf(String key);

  /// Whether [key] was declared `secure`. Secure keys are never sent by
  /// `bodyFromState`. Stores without secure keys keep the default.
  bool isSecure(String key) => false;

  void dispose();
}
