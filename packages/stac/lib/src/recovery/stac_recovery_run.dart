import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:stac/src/framework/stac_service.dart';
import 'package:stac/src/recovery/stac_error_envelope.dart';
import 'package:stac/src/recovery/stac_recovery_exception.dart';
import 'package:stac/src/recovery/stac_recovery_instruction.dart';
import 'package:stac/src/recovery/stac_request_template.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_logger/stac_logger.dart';

/// `RequestOptions.extra` key holding the [StacRecoveryRun] a request was made
/// *directly* by (a `networkRequest` that `recover` runs itself, not one of
/// its callbacks). Read when the options are built, like the exemption (M3);
/// the interceptor uses it to deduce the run result (M6).
const String stacRecoveryRunExtraKey = 'stac.recovery.run';

/// Default `timeoutMs` of a recovery.
const int stacRecoveryDefaultTimeoutMs = 20000;

const Symbol _runKey = #stacRecoveryRun;
const Symbol _directKey = #stacRecoveryDirect;

/// Actions that need a mounted screen; they are skipped (with a log) when the
/// scope of the run lost its screen.
const Set<String> _needsMountedScreen = {
  'navigate',
  'showDialog',
  'showModalBottomSheet',
  'showSnackBar',
  'getFormValue',
  'validateForm',
};

/// Actions that open something and finish only when it is closed; started
/// and not awaited.
const Set<String> _openingActions = {
  'navigate',
  'showDialog',
  'showModalBottomSheet',
};

const Symbol _detachKey = #stacRecoveryDetachOpening;

/// Whether an action of [actionType] called right now must be started and
/// not awaited: it opens something (route, dialog, sheet) whose future only
/// completes when it is closed, and we are inside the `recover` / hook of a
/// recovery. Holds at any nesting level (e.g. inside a `multiAction`), so a
/// `pushAndRemoveAll` can never keep the run, and its identity, open.
bool stacDetachesOpening(String actionType) =>
    Zone.current[_detachKey] == true && _openingActions.contains(actionType);

/// Detaches [pending] (see [stacDetachesOpening]): logs its failure and
/// returns `null` so the caller goes on.
Object? stacDetach(Object? pending) {
  if (pending is Future) {
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object e) => Log.e(
          StacGlobalState.instance.redact('recovery action failed: $e'),
        ),
      ),
    );
  }
  return null;
}

/// Runs [fn] so that requests it makes are no longer *direct* requests of the
/// current recovery (they belong to a callback such as `onSuccess`). Outside a
/// recovery it just calls [fn].
T stacRunNested<T>(T Function() fn) => StacRecoveryRun.current == null
    ? fn()
    : runZoned(fn, zoneValues: {_directKey: false});

/// The scope used when a request has no template (the app's own Dio): the
/// global scope, under the root element. `null` when there is no mounted
/// app.
StacCapturedScope? _rootScope() {
  try {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null || !root.mounted) return null;
    return StacCapturedScope.capture(root);
  } catch (_) {
    return null;
  }
}

/// One request that failed with this run's instruction and waits for it.
class StacRecoveryParticipant {
  StacRecoveryParticipant({
    required this.options,
    required this.error,
    this.template,
  });

  final RequestOptions options;

  /// The error that brought it here.
  final DioException error;

  /// Its template (`null` for the app's own Dio requests).
  final StacRequestTemplate? template;

  /// Whether the request is still wanted: not cancelled and its screen is
  /// alive.
  bool get alive =>
      template?.isAlive ?? !(options.cancelToken?.isCancelled ?? false);

  /// Where this request's actions run: its captured scope, or the app root.
  StacCapturedScope? get scope => template?.scope ?? _rootScope();
}

/// One recovery shared by every request that failed with the same identity:
/// runs `recover` once (in the scope of the leader), decides the result and
/// runs `onFailure` / `onUnavailable` once.
class StacRecoveryRun {
  StacRecoveryRun({
    required this.identity,
    required this.instruction,
    this.label,
  });

  /// Coalescing identity; `null` when coalescing is off (`key: null`).
  final String? identity;

  /// Short, safe-to-log name of the identity.
  final String? label;
  final StacRecoveryInstruction instruction;

  final List<StacRecoveryParticipant> participants = [];

  final Completer<void> _completed = Completer<void>();
  StacRecoveryResult? _result;
  StacRecoveryResult? _emitted;
  String? _emittedCondition;
  bool _closed = false;
  bool _sawUnavailable = false;
  bool _sawFailure = false;
  DioException? _lastObserved;

  /// Completes when the run is over, `onFailure` / `onUnavailable` included.
  Future<void> get completed => _completed.future;

  /// The result, once decided.
  StacRecoveryResult? get result => _result;

  /// Whether `onFailure` ran (once, for the first request still alive).
  bool onFailureRan = false;

  /// Whether `onUnavailable` ran.
  bool onUnavailableRan = false;

  /// The last failed request seen among the ones `recover` made directly.
  DioException? get lastObservedError => _lastObserved;

  /// The run whose `recover` is executing in this zone (also inside the
  /// callbacks of its requests), or `null`.
  static StacRecoveryRun? get current {
    final run = Zone.current[_runKey];
    return run is StacRecoveryRun ? run : null;
  }

  /// [current], unless the zone belongs to a callback of a request.
  static StacRecoveryRun? get currentDirect =>
      Zone.current[_directKey] == true ? current : null;

  /// Emits the explicit result of the running recovery (`recoveryOutcome`):
  /// the first emission wins; later ones, and ones after the run decided,
  /// are ignored. [condition] is only kept for logs. Returns whether this
  /// emission was taken.
  bool emit(StacRecoveryResult result, {String? condition}) {
    if (_closed || _emitted != null) return false;
    _emitted = result;
    _emittedCondition = condition;
    return true;
  }

  /// Emits on the run of the current zone; `false` (and a log) when called
  /// outside a recovery.
  static bool emitCurrent(StacRecoveryResult result, {String? condition}) {
    final run = current;
    if (run == null) {
      Log.w('recoveryOutcome called outside a recovery; ignored');
      return false;
    }
    return run.emit(result, condition: condition);
  }

  /// A request of `recover` finished with an error (called by the
  /// interceptor).
  void observeError(DioException error) {
    if (_closed || error.type == DioExceptionType.cancel) return;
    final status = error.response?.statusCode;
    if (status == null || status >= 500) {
      _sawUnavailable = true;
    } else {
      _sawFailure = true;
    }
    _lastObserved = error;
  }

  /// Default result (M6): 5xx / timeout / network = unavailable; else 4xx (or
  /// any other error) = failure; else success.
  StacRecoveryResult _deduce() => _sawUnavailable
      ? StacRecoveryResult.unavailable
      : _sawFailure
      ? StacRecoveryResult.failure
      : StacRecoveryResult.success;

  /// First participant still wanted, or `null`.
  StacRecoveryParticipant? get firstAlive {
    for (final p in participants) {
      if (p.alive) return p;
    }
    return null;
  }

  /// Runs the recovery led by [leader]; [onResult] is called as soon as the
  /// result is decided (before `onFailure` / `onUnavailable`). Never throws.
  Future<void> execute(
    StacRecoveryParticipant leader, {
    required void Function(StacRecoveryResult result) onResult,
  }) async {
    try {
      final scope = leader.scope;
      var timedOut = false;
      var threw = false;
      if (scope == null) {
        Log.w('recovery: no screen to run "recover" in; treated as failure');
        threw = true;
      } else {
        // The recovery outlives the screen of its leader: its requests must
        // not be cancelled with it.
        final own = scope.withOwnRequests();
        final timeout = Duration(
          milliseconds: (instruction.timeoutMs ?? 0) > 0
              ? instruction.timeoutMs!
              : stacRecoveryDefaultTimeoutMs,
        );
        try {
          await _runActions(
            instruction.recover,
            own,
            leader,
            attachRun: true,
          ).timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              own.requests.cancelAll();
            },
          );
        } catch (e) {
          threw = true;
          Log.e(
            StacGlobalState.instance.redact('recovery "recover" failed: $e'),
          );
        }
      }
      final result =
          _emitted ??
          (timedOut
              ? StacRecoveryResult.unavailable
              : threw
              ? StacRecoveryResult.failure
              : _deduce());
      _closed = true;
      _result = result;
      Log.w(
        'recovery ${label ?? '(uncoalesced)'}: ${result.name}'
        '${_emittedCondition == null ? '' : ' ($_emittedCondition)'}'
        '${timedOut ? ' [timeout]' : ''}',
      );
      onResult(result);
      await _runHook(result);
    } catch (e) {
      Log.e(StacGlobalState.instance.redact('recovery run crashed: $e'));
      _closed = true;
      _result ??= StacRecoveryResult.failure;
    } finally {
      if (!_completed.isCompleted) _completed.complete();
    }
  }

  /// `onFailure` / `onUnavailable`: once, in the scope of the first request
  /// still alive, exempt from recovery (G7-B). Nothing runs when no request
  /// is alive. Hook for the caller of `recoveryOutcome` (T4).
  Future<void> _runHook(StacRecoveryResult result) async {
    final actions = switch (result) {
      StacRecoveryResult.failure => instruction.onFailure,
      StacRecoveryResult.unavailable => instruction.onUnavailable,
      StacRecoveryResult.success => null,
    };
    if (actions == null) return;
    final who = firstAlive;
    final scope = who?.scope;
    if (who == null || scope == null) {
      Log.w('recovery: no live request to run ${result.name} hook for');
      return;
    }
    if (result == StacRecoveryResult.failure) {
      onFailureRan = true;
    } else {
      onUnavailableRan = true;
    }
    try {
      await _runActions(actions, scope, who, attachRun: false);
    } catch (e) {
      Log.e(StacGlobalState.instance.redact('recovery hook failed: $e'));
    }
  }

  Future<void> _runActions(
    Object actions,
    StacCapturedScope scope,
    StacRecoveryParticipant who, {
    required bool attachRun,
  }) {
    final vars = <String, Object?>{
      'request': _requestVars(who.options),
      'failure': _failureVars(who.error),
    };
    Future<void> body() => runZoned(
      () => runWithStacActionVars<void>(vars, () async {
        final list = actions is List ? actions : [actions];
        final context = scope.origin;
        for (final action in list) {
          if (action is! Map) {
            Log.e(
              StacGlobalState.instance.redact(
                'recovery expects actions, got $action',
              ),
            );
            continue;
          }
          final json = Map<String, dynamic>.from(action);
          final type = json['actionType'];
          if (!context.mounted && _needsMountedScreen.contains(type)) {
            Log.w('recovery: action "$type" skipped (its screen is gone)');
            continue;
          }
          // Opening actions are detached by StacService.onCallFromJson (zone).
          await StacService.onCallFromJson(json, context);
        }
      }),
      zoneValues: {_detachKey: true},
    );
    return runWithStacCapturedScope<void>(
      scope,
      () => runExempt<void>(
        () => attachRun
            ? runZoned(body, zoneValues: {_runKey: this, _directKey: true})
            : body(),
      ),
    );
  }
}

/// `request` as seen by bindings in `recover` / `onFailure`: read-only.
Map<String, Object?> _requestVars(RequestOptions o) => Map.unmodifiable({
  'method': o.method,
  'url': o.uri.toString(),
  'path': o.path,
  'queryParameters': Map<String, Object?>.of(o.queryParameters),
  'headers': Map<String, Object?>.of(o.headers),
  'body': _jsonLike(o.data) ? o.data : null,
});

/// `failure` as seen by bindings: the response that started the recovery,
/// `{statusCode, body, headers, code, message}`.
Map<String, Object?> _failureVars(DioException e) {
  final response = e.response;
  Object? body = response?.data;
  if (body is String) {
    try {
      body = jsonDecode(body);
    } catch (_) {
      // Not JSON: keep the text.
    }
  }
  final StacErrorEnvelope? envelope = stacEnvelopeOf(e);
  return Map.unmodifiable({
    'statusCode': response?.statusCode,
    'body': body,
    'headers': {
      for (final h
          in response?.headers.map.entries ??
              const <MapEntry<String, List<String>>>[])
        h.key: h.value,
    },
    'code': envelope?.code,
    'message': envelope?.message,
  });
}

bool _jsonLike(Object? v) =>
    v == null || v is String || v is num || v is bool || v is Map || v is List;
