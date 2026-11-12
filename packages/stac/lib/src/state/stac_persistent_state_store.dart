import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/src/state/stac_state_persistence.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

/// Memory store whose `persist`/`secure` keys survive restarts.
///
/// Value precedence (Plano 5.1.2): memory > persisted > initial. A persisted
/// value of a key nobody declared yet waits in `pending` and only shows up
/// when the key is declared. Changes are written as JSON, coalesced per
/// microtask; [reset] erases the persisted copy.
///
/// Secure values are never logged: only key names appear in messages.
class StacPersistentStateStore extends StacMemoryStateStore {
  StacPersistentStateStore({
    StacStatePersistence? persistence,
    StacStatePersistence? securePersistence,
  }) {
    configure(persistence: persistence, securePersistence: securePersistence);
  }

  StacStatePersistence? _persistence;
  StacStatePersistence? _securePersistence;

  final Map<String, StacKeyFlags> _flags = {};
  final Map<String, String> _pendingPlain = {};
  final Map<String, String> _pendingSecure = {};
  final Set<String> _toWrite = {};
  bool _flushScheduled = false;
  // Created on first use, so it lives in the zone that triggers the work.
  Future<void>? _tail;

  /// Sets the storages used from now on (before [hydrate]).
  void configure({
    StacStatePersistence? persistence,
    StacStatePersistence? securePersistence,
  }) {
    _persistence = persistence ?? _persistence;
    _securePersistence = securePersistence ?? _securePersistence;
  }

  /// Loads every persisted entry (D14). Never throws: a failing storage is
  /// logged and treated as empty.
  Future<void> hydrate() async {
    await _load(_persistence, _pendingPlain, 'persisted');
    await _load(_securePersistence, _pendingSecure, 'secure');
  }

  Future<void> _load(
    StacStatePersistence? source,
    Map<String, String> into,
    String label,
  ) async {
    if (source == null) return;
    try {
      final all = await source.readAll();
      all.forEach((key, raw) {
        // Memory wins: a key declared meanwhile keeps its value.
        if (!has(key)) into[key] = raw;
      });
    } catch (e) {
      Log.e('Failed to read $label global state: $e');
    }
  }

  @override
  bool isSecure(String key) => _flags[key]?.secure ?? false;

  @override
  void declare(String key, Object? initial) =>
      declareWithFlags(key, initial, const StacKeyFlags());

  @override
  void declareWithFlags(String key, Object? initial, StacKeyFlags flags) {
    if (has(key)) return;
    super.declare(key, initial);
    if (!has(key)) return; // reserved name
    final persists = flags.persist || flags.secure;
    if (!persists) return;
    final effective = StacKeyFlags(persist: true, secure: flags.secure);
    _flags[key] = effective;
    final raw = (effective.secure ? _pendingSecure : _pendingPlain).remove(key);
    if (raw == null) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      Log.w('Persisted value of global key "$key" is invalid; discarded.');
      _enqueueDelete(key);
      return;
    }
    if (!_compatible(initial, decoded)) {
      Log.w(
        'Persisted value of global key "$key" does not match the declared '
        'type; discarded, using the initial value.',
      );
      _enqueueDelete(key);
      return;
    }
    super.write(key, decoded);
  }

  /// `null` initial accepts anything; otherwise the JSON kind must match.
  static bool _compatible(Object? initial, Object? persisted) {
    if (initial == null) return true;
    if (initial is num) return persisted is num;
    if (initial is String) return persisted is String;
    if (initial is bool) return persisted is bool;
    if (initial is List) return persisted is List;
    if (initial is Map) return persisted is Map;
    return false;
  }

  @override
  bool write(String key, Object? value) {
    final ok = super.write(key, value);
    if (ok && _flags.containsKey(key)) _scheduleWrite(key);
    return ok;
  }

  @override
  void reset(String key) {
    super.reset(key);
    onReset(key);
  }

  /// Called after [reset] restored the initial value of [key]: the persisted
  /// copy (if any) is erased.
  @protected
  void onReset(String key) {
    if (!_flags.containsKey(key)) return;
    _toWrite.remove(key);
    _enqueueDelete(key);
  }

  StacStatePersistence? _storageFor(String key) =>
      (_flags[key]?.secure ?? false) ? _securePersistence : _persistence;

  void _scheduleWrite(String key) {
    _toWrite.add(key);
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    final keys = _toWrite.toList();
    _toWrite.clear();
    for (final key in keys) {
      final storage = _storageFor(key);
      if (storage == null) continue;
      final String encoded;
      try {
        encoded = jsonEncode(read(key));
      } catch (_) {
        Log.e('Global key "$key" holds a value that cannot be persisted.');
        continue;
      }
      _enqueue(() => storage.write(key, encoded), key, 'write');
    }
  }

  void _enqueueDelete(String key) {
    final storage = _storageFor(key) ?? _persistence;
    if (storage == null) return;
    _enqueue(() => storage.delete(key), key, 'delete');
  }

  /// Storage operations run one after the other, in call order.
  void _enqueue(Future<void> Function() op, String key, String what) {
    _tail = (_tail ?? Future<void>.value()).then((_) => op()).catchError((
      Object e,
    ) {
      Log.e('Failed to $what persisted global key "$key": $e');
    });
  }

  /// Completes when every scheduled write/delete has reached the storage.
  Future<void> flush() {
    if (_flushScheduled) _flush();
    return _tail ?? Future<void>.value();
  }

  /// Plain-text leaves of every secure value, for log redaction.
  Iterable<String> secretStrings() sync* {
    for (final entry in _flags.entries) {
      if (!entry.value.secure) continue;
      yield* _leafStrings(read(entry.key));
    }
  }

  static Iterable<String> _leafStrings(Object? value) sync* {
    if (value is String) {
      if (value.isNotEmpty) yield value;
    } else if (value is Map) {
      for (final v in value.values) {
        yield* _leafStrings(v);
      }
    } else if (value is List) {
      for (final v in value) {
        yield* _leafStrings(v);
      }
    }
  }

  @visibleForTesting
  bool hasPending(String key) =>
      _pendingPlain.containsKey(key) || _pendingSecure.containsKey(key);
}
