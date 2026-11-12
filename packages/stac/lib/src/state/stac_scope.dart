import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:stac/src/state/expression/stac_expression.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/src/state/stac_state_store.dart';

/// Lexical variables (`item`, `index`, `params`, ...). Merges with the
/// enclosing [StacLocalScope]; inner variables shadow outer ones.
class StacLocalScope extends InheritedWidget {
  const StacLocalScope({required this.vars, required super.child, super.key});

  final Map<String, Object?> vars;

  /// Variables visible at [context] (outer + own), without registering a
  /// dependency.
  static Map<String, Object?> varsOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StacLocalScope>();
    if (scope == null) return const {};
    final element = context
        .getElementForInheritedWidgetOfExactType<StacLocalScope>()!;
    final parent = _parentVars(element);
    return {...parent, ...scope.vars};
  }

  static Map<String, Object?> _parentVars(InheritedElement element) {
    final parent = <String, Object?>{};
    element.visitAncestorElements((ancestor) {
      if (ancestor is InheritedElement && ancestor.widget is StacLocalScope) {
        parent
          ..addAll(_parentVars(ancestor))
          ..addAll((ancestor.widget as StacLocalScope).vars);
        return false;
      }
      return true;
    });
    return parent;
  }

  @override
  bool updateShouldNotify(StacLocalScope oldWidget) =>
      !_sameVars(vars, oldWidget.vars);
}

bool _sameVars(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || !identical(b[e.key], e.value)) return false;
  }
  return true;
}

/// One [CancelToken] per request key (used by networkRequest).
class StacRequestRegistry {
  final Map<String, CancelToken> _tokens = {};

  /// Cancels the in-flight request with [key] (if any) and returns a fresh
  /// token for the new one.
  CancelToken begin(String key) {
    _tokens[key]?.cancel('superseded');
    return _tokens[key] = CancelToken();
  }

  void cancelAll() {
    for (final t in _tokens.values) {
      t.cancel('disposed');
    }
    _tokens.clear();
  }
}

class _StacStateInherited extends InheritedWidget {
  const _StacStateInherited({
    required this.store,
    required this.requests,
    required super.child,
  });

  final StacStateStore store;
  final StacRequestRegistry requests;

  @override
  bool updateShouldNotify(_StacStateInherited oldWidget) => false;
}

/// Owns the screen state store.
class StacStateScope extends StatefulWidget {
  const StacStateScope({
    required this.initialState,
    required this.child,
    this.onInit,
    super.key,
  });

  /// Keys declared when the scope is created.
  final Map<String, Object?> initialState;

  /// Executed by the screen binding (Task 6); not run here.
  final Object? onInit;

  final Widget child;

  /// Nearest screen store, without creating a rebuild dependency.
  static StacStateStore? storeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_StacStateInherited>()?.store;

  static StacRequestRegistry requestsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_StacStateInherited>()?.requests ??
      _orphanRequests;

  static final StacRequestRegistry _orphanRequests = StacRequestRegistry();

  @override
  State<StacStateScope> createState() => _StacStateScopeState();
}

class _StacStateScopeState extends State<StacStateScope> {
  late final StacStateStore _store;
  final StacRequestRegistry _requests = StacRequestRegistry();

  @override
  void initState() {
    super.initState();
    _store = StacMemoryStateStore();
    widget.initialState.forEach(_store.declare);
  }

  @override
  void dispose() {
    _requests.cancelAll();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StacStateInherited(
    store: _store,
    requests: _requests,
    child: widget.child,
  );
}

/// Live read-only view of the global store (`global.x` in expressions).
class StacGlobalView extends MapBase<String, Object?> {
  StacGlobalView(this._store);

  final StacStateStore _store;

  @override
  Object? operator [](Object? key) => key is String ? _store.read(key) : null;

  @override
  bool containsKey(Object? key) => key is String && _store.has(key);

  @override
  Iterable<String> get keys => const [];

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('global view is read-only');

  @override
  void clear() => throw UnsupportedError('global view is read-only');

  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('global view is read-only');
}

/// Read/write facade used by bindings and actions.
class StacScope implements StacEvalContext {
  StacScope._(this._locals, this._screen, this._global);

  /// Snapshot of the scopes at [context]. Creates no dependency on the state
  /// scope (only the local variables are read, also without dependency).
  factory StacScope.of(BuildContext context) {
    final locals = {
      ...StacLocalScope.varsOf(context),
      ...currentStacActionVars(),
    };
    return StacScope._(
      locals,
      StacStateScope.storeOf(context),
      StacGlobalState.instance.store,
    );
  }

  final Map<String, Object?> _locals;
  final StacStateStore? _screen;
  final StacStateStore _global;

  /// D4: local variables > `global` > screen key.
  @override
  Object? lookup(String root) {
    if (_locals.containsKey(root)) return _locals[root];
    if (root == 'global') return StacGlobalView(_global);
    return _screen?.read(root);
  }

  StacEvalContext get evalContext => this;

  /// Whether [root] is a lexical variable (`item`, `params`, ...) rather than
  /// a state key.
  bool isLocal(String root) => _locals.containsKey(root);

  /// Store keys (`k`, `global.k`) the [dependencies] refer to.
  List<Listenable> listenablesFor(Set<String> dependencies) {
    final result = <Listenable>[];
    for (final dep in dependencies) {
      final ValueListenable<Object?>? l;
      if (dep.startsWith('global.')) {
        l = _global.listenable(dep.substring(7));
      } else if (_locals.containsKey(dep) || dep == 'global') {
        l = null;
      } else {
        l = _screen?.listenable(dep);
      }
      if (l != null) result.add(l);
    }
    return result;
  }

  StacStateStore? storeFor(String path) =>
      path.startsWith('global.') ? _global : _screen;

  /// `k` writes the screen store, `global.k` the global one.
  bool write(String path, Object? value) {
    final isGlobal = path.startsWith('global.');
    final store = isGlobal ? _global : _screen;
    if (store == null) return false;
    return store.write(isGlobal ? path.substring(7) : path, value);
  }
}
