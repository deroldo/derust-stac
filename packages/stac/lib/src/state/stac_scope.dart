import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:stac/src/framework/stac_service.dart';
import 'package:stac/src/state/expression/stac_expression.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

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

/// One [CancelToken] per request key (used by networkRequest), plus the
/// tokens of keyless requests, so that closing the screen cancels them all.
class StacRequestRegistry {
  final Map<String, CancelToken> _tokens = {};
  final Set<CancelToken> _anonymous = {};

  /// Cancels the in-flight request with [key] (if any) and returns a fresh
  /// token for the new one.
  CancelToken begin(String key) {
    _tokens[key]?.cancel('superseded');
    return _tokens[key] = CancelToken();
  }

  /// Token for a request without key; released by [finish].
  CancelToken beginAnonymous() {
    final token = CancelToken();
    _anonymous.add(token);
    return token;
  }

  /// Cancels the in-flight request with [key]. Returns whether one existed.
  bool cancel(String key) {
    final token = _tokens.remove(key);
    if (token == null) return false;
    token.cancel('cancelRequest');
    return true;
  }

  /// Releases [token] once its request is over (no-op if it was superseded
  /// by a newer request with the same key).
  void finish(String? key, CancelToken token) {
    if (key != null && identical(_tokens[key], token)) _tokens.remove(key);
    _anonymous.remove(token);
  }

  void cancelAll() {
    for (final t in _tokens.values) {
      t.cancel('disposed');
    }
    for (final t in _anonymous) {
      t.cancel('disposed');
    }
    _tokens.clear();
    _anonymous.clear();
  }

  @visibleForTesting
  int get pendingCount => _tokens.length + _anonymous.length;
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
    this.globalState = const {},
    this.onInit,
    super.key,
  });

  /// Keys declared when the scope is created. Values may hold bindings over
  /// `params`/`global`; they are resolved once, at creation.
  final Map<String, Object?> initialState;

  /// `globalState` block (D12), declared idempotently before [initialState].
  final Map<String, Object?> globalState;

  /// One action or a list of actions (list = `multiAction` with `sync`),
  /// run once after the first frame, with a context below this scope.
  final Object? onInit;

  final Widget child;

  /// Nearest screen store, without creating a rebuild dependency.
  static StacStateStore? storeOf(BuildContext context) {
    final captured = StacCapturedScope.forContext(context);
    if (captured != null) return captured.scope._screen;
    return context.getInheritedWidgetOfExactType<_StacStateInherited>()?.store;
  }

  static StacRequestRegistry requestsOf(BuildContext context) {
    final captured = StacCapturedScope.forContext(context);
    if (captured != null) return captured.requests;
    return context
            .getInheritedWidgetOfExactType<_StacStateInherited>()
            ?.requests ??
        _orphanRequests;
  }

  static final StacRequestRegistry _orphanRequests = StacRequestRegistry();

  /// Captures the scopes visible at [origin] (screen store and local
  /// variables) and returns a function that re-provides them around a widget
  /// built elsewhere, such as the content of a dialog or bottom sheet (which
  /// lives under the Navigator, outside the screen). Nothing is owned or
  /// disposed here: the stores belong to the origin screen.
  static Widget Function(Widget child) reprovider(BuildContext origin) {
    final inherited = origin
        .getInheritedWidgetOfExactType<_StacStateInherited>();
    final locals = StacLocalScope.varsOf(origin);
    return (child) {
      var result = child;
      if (locals.isNotEmpty) {
        result = StacLocalScope(vars: locals, child: result);
      }
      if (inherited != null) {
        result = _StacStateInherited(
          store: inherited.store,
          requests: inherited.requests,
          child: result,
        );
      }
      return result;
    };
  }

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
    if (widget.globalState.isNotEmpty) {
      StacGlobalState.instance.declareAll(widget.globalState);
    }
    final initial = widget.initialState.isEmpty
        ? widget.initialState
        : _resolveInitial(widget.initialState);
    initial.forEach(
      (key, value) => _store.declare(key, _screenInitial(key, value)),
    );
    if (widget.onInit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runOnInit());
    }
  }

  /// Only global keys persist (Plano 5.1.2): a declaration object with
  /// `persist`/`secure` on a screen key is logged and reduced to its `initial`.
  static Object? _screenInitial(String key, Object? value) {
    if (value is Map &&
        value.containsKey('initial') &&
        (value.containsKey('persist') || value.containsKey('secure')) &&
        value.keys.every(const {'initial', 'persist', 'secure'}.contains)) {
      Log.w(
        'State key "$key": persist/secure only apply to globalState keys; '
        'ignored.',
      );
      return value['initial'];
    }
    return value;
  }

  /// Initial values resolved once against `params`/`global` (data, so no
  /// "skip children" rule: `initial` is a deep data key).
  Map<String, Object?> _resolveInitial(Map<String, Object?> initial) {
    try {
      final wrapper = StacBinding.resolve(
        {'initial': initial},
        StacScope.of(context),
        isAction: true,
      );
      return Map<String, Object?>.from((wrapper as Map)['initial'] as Map);
    } catch (e) {
      Log.e('Failed to resolve initial state: $e');
      return initial;
    }
  }

  void _runOnInit() {
    final inner = _innerContext;
    if (!mounted || inner == null || !inner.mounted) return;
    final onInit = widget.onInit;
    final Map<String, dynamic> action;
    if (onInit is Map) {
      action = Map<String, dynamic>.from(onInit);
    } else if (onInit is List) {
      action = {'actionType': 'multiAction', 'sync': true, 'actions': onInit};
    } else {
      Log.e(
        StacGlobalState.instance.redact(
          'onInit must be an action or a list of actions, got $onInit',
        ),
      );
      return;
    }
    StacService.onCallFromJson(action, inner);
  }

  BuildContext? _innerContext;

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
    // Context below the inherited widget, for onInit (T5 note).
    child: Builder(
      builder: (context) {
        _innerContext = context;
        return widget.child;
      },
    ),
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
    final captured = StacCapturedScope.forContext(context);
    if (captured != null) {
      // Inside a captured action chain (networkRequest callbacks): the scope
      // seen at trigger time, plus the variables of the current action.
      return StacScope._(
        {...captured.scope._locals, ...currentStacActionVars()},
        captured.scope._screen,
        captured.scope._global,
      );
    }
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

const Symbol _capturedScopeKey = #stacCapturedScope;

/// The scopes visible where an action chain was triggered: lexical variables
/// (`item`, `index`, ...), the screen store and the request registry.
///
/// A `networkRequest` outlives the widget that triggered it (an optimistic
/// delete removes the button, a dialog button closes its dialog, a
/// `pushReplacement` replaces the screen), but its callbacks must still see
/// the trigger-time scopes, not whatever that widget's element is now showing.
/// The chain runs inside [runWithStacCapturedScope]; while it does,
/// `StacScope.of`, `StacStateScope.storeOf` and `StacStateScope.requestsOf`
/// answer from this capture for [origin] instead of from the (possibly
/// unmounted, or reused) element.
class StacCapturedScope {
  StacCapturedScope._(this.origin, this.scope, this.requests);

  /// The context that triggered the chain.
  final BuildContext origin;

  /// Whether the origin was inside a screen state scope. Screens that closed
  /// cancel their requests, so only those are discarded by cancellation;
  /// without a screen the old "widget still mounted" rule applies.
  bool get hasScreenStore => scope._screen != null;

  final StacScope scope;
  final StacRequestRegistry requests;

  /// Captures the scopes visible at [context]. Nested chains started from the
  /// same context reuse the enclosing capture.
  static StacCapturedScope capture(BuildContext context) =>
      forContext(context) ??
      StacCapturedScope._(
        context,
        StacScope.of(context),
        StacStateScope.requestsOf(context),
      );

  /// The capture of the running chain, when [context] is its origin.
  static StacCapturedScope? forContext(BuildContext context) {
    final captured = Zone.current[_capturedScopeKey];
    return captured is StacCapturedScope && identical(captured.origin, context)
        ? captured
        : null;
  }
}

/// Runs [body] (and its async continuations) with [captured] active.
Future<T> runWithStacCapturedScope<T>(
  StacCapturedScope captured,
  FutureOr<T> Function() body,
) => runZoned(
  () async => await body(),
  zoneValues: {_capturedScopeKey: captured},
);
