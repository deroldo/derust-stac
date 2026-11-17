import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:stac/src/recovery/stac_envelope_recognizer.dart';
import 'package:stac/src/recovery/stac_error_envelope.dart';
import 'package:stac/src/recovery/stac_recovery_exception.dart';
import 'package:stac/src/recovery/stac_recovery_instruction.dart';
import 'package:stac/src/recovery/stac_recovery_run.dart';
import 'package:stac/src/recovery/stac_request_template.dart';
import 'package:stac/src/services/stac_network_service.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac_logger/stac_logger.dart';

/// What the interceptor hands the Dio chain: a response that resolves the
/// request, or the error it ends with.
typedef _Outcome = ({Response<dynamic>? response, DioException? error});

/// Installed on the app's Dio by `StacNetworkService.initialize`.
///
/// Reads the server error envelope of a failed response and, when it carries
/// a `recovery` instruction, runs it (coalesced by identity), sends the
/// request again once and hands the caller the final result. It knows
/// nothing about tokens, sessions or statuses: it only follows the
/// instruction.
///
/// What it never recovers: errors without a response (network, timeout),
/// requests exempt from recovery (the repetition, `recover`, `onFailure`...),
/// responses without a recognized envelope or without `recovery`, requests no
/// longer wanted, and bodies that cannot be sent twice. Those pass on as the
/// plain error (with the envelope attached to the response, see
/// [stacEnvelopeOf]).
class StacRecoveryInterceptor extends Interceptor {
  StacRecoveryInterceptor();

  /// The one instance installed on the app's Dio.
  static final StacRecoveryInterceptor instance = StacRecoveryInterceptor();

  /// Monotonic order of events: request starts and recovery successes.
  int _clock = 0;
  final Expando<int> _started = Expando<int>('stac.recovery.started');

  /// Runs in flight, by identity (only coalesced ones).
  final Map<String, StacRecoveryRun> _runs = {};

  /// When the last successful recovery of an identity ended (`_clock`). A
  /// request that started before it already carries stale data: it only
  /// needs its repetition.
  final Map<String, int> _lastSuccess = {};

  @visibleForTesting
  void reset() {
    _runs.clear();
    _lastSuccess.clear();
  }

  @visibleForTesting
  int get runsInFlight => _runs.length;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _started[options] = ++_clock;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_onError(err, handler));
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final outcome = await _process(err);
      final response = outcome.response;
      if (response != null) {
        handler.resolve(response);
      } else {
        handler.next(outcome.error ?? err);
      }
    } catch (e) {
      Log.e(StacGlobalState.instance.redact('recovery interceptor failed: $e'));
      handler.next(err);
    }
  }

  Future<_Outcome> _process(DioException err) async {
    final options = err.requestOptions;
    final direct = options.extra[stacRecoveryRunExtraKey];
    if (direct is StacRecoveryRun) direct.observeError(err);

    final response = err.response;
    if (response == null || err.type == DioExceptionType.cancel) {
      return (response: null, error: err);
    }
    final envelope = _attach(response);
    final instruction = envelope?.recovery;
    if (envelope == null || instruction == null) {
      return (response: null, error: err);
    }
    if (stacRecoveryExempt(options)) return (response: null, error: err);

    final template = StacRequestTemplate.of(options);
    final participant = StacRecoveryParticipant(
      options: options,
      error: err,
      template: template,
    );
    if (!participant.alive) return (response: null, error: err);
    if (stacRetryUnsafe(options)) {
      Log.w(
        'recovery skipped: the request body (stream/form data) cannot be '
        'sent twice',
      );
      return (response: null, error: err);
    }

    final identity = instruction.keyDisabled ? null : _identity(instruction);
    var run = identity == null ? null : _runs[identity];
    if (run == null) {
      final last = identity == null ? null : _lastSuccess[identity];
      final started = _started[options];
      if (last != null && started != null && started < last) {
        // A recovery succeeded after this request started: its data is stale
        // and the shared recovery is done. Only send it again.
        return _repeat(err, instruction, null);
      }
      if (participant.scope == null) {
        Log.w('recovery skipped: no screen to run "recover" in');
        return (response: null, error: err);
      }
      run = StacRecoveryRun(
        identity: identity,
        instruction: instruction,
        label: identity == null ? null : _label(instruction, identity),
      )..participants.add(participant);
      if (identity != null) _runs[identity] = run;
      final started0 = run;
      unawaited(
        run
            .execute(
              participant,
              onResult: (result) {
                if (result == StacRecoveryResult.success && identity != null) {
                  _lastSuccess[identity] = ++_clock;
                }
              },
            )
            .whenComplete(() {
              if (identity != null && identical(_runs[identity], started0)) {
                _runs.remove(identity);
              }
            }),
      );
    } else {
      run.participants.add(participant);
    }

    await _waitFor(run, options.cancelToken);
    if (!participant.alive) return (response: null, error: _cancelled(options));

    switch (run.result) {
      case StacRecoveryResult.success:
        return _repeat(err, instruction, run);
      case StacRecoveryResult.failure:
      case StacRecoveryResult.unavailable:
      case null:
        final last = run.lastObservedError ?? err;
        return (
          response: null,
          error: StacRecoveryException(
            original: err,
            lastError: last,
            result: run.result ?? StacRecoveryResult.failure,
            envelope: stacEnvelopeOf(last),
            onFailureRan: run.onFailureRan,
            onUnavailableRan: run.onUnavailableRan,
          ),
        );
    }
  }

  /// Sends the request again, once. Its success resolves the request; its
  /// failure is the final error and is not recovered again (the repetition is
  /// exempt).
  Future<_Outcome> _repeat(
    DioException err,
    StacRecoveryInstruction instruction,
    StacRecoveryRun? run,
  ) async {
    final retry = instruction.retry;
    final overrides = retry == null
        ? null
        : <String, dynamic>{
            if (retry.headers != null) 'headers': retry.headers,
            if (retry.queryParameters != null)
              'queryParameters': retry.queryParameters,
            if (retry.hasBody) 'body': retry.body,
          };
    DioException failed;
    try {
      final response = await StacNetworkService.retryRequest(
        err.requestOptions,
        overrides: overrides,
        removeHeaders: retry?.removeHeaders,
      );
      if (response != null) return (response: response, error: null);
      return (response: null, error: err);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return (response: null, error: e);
      failed = e;
    } catch (e, st) {
      Log.e(StacGlobalState.instance.redact('recovery repetition failed: $e'));
      failed = DioException(
        requestOptions: err.requestOptions,
        type: DioExceptionType.unknown,
        error: e,
        stackTrace: st,
      );
    }
    return (
      response: null,
      error: StacRecoveryException(
        original: err,
        lastError: failed,
        result: run?.result ?? StacRecoveryResult.success,
        envelope: stacEnvelopeOf(failed),
        retried: true,
      ),
    );
  }

  /// Waits for [run], or for [token] being cancelled, whichever is first.
  Future<void> _waitFor(StacRecoveryRun run, CancelToken? token) async {
    if (token == null) return run.completed;
    await Future.any<void>([
      run.completed,
      token.whenCancel.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  DioException _cancelled(RequestOptions options) =>
      DioException.requestCancelled(
        requestOptions: options,
        reason:
            options.cancelToken?.cancelError?.error ??
            'request no longer wanted during recovery',
      );

  /// The envelope of [response], recognized once and left in its `extra`.
  StacErrorEnvelope? _attach(Response<dynamic> response) {
    final known = response.extra[stacEnvelopeExtraKey];
    if (known is StacErrorEnvelope) return known;
    final envelope = StacEnvelopeRecognizer.recognize(response);
    if (envelope != null) {
      try {
        response.extra[stacEnvelopeExtraKey] = envelope;
      } catch (_) {
        // Unmodifiable extra: the envelope is still used for this error.
      }
    }
    return envelope;
  }

  /// Coalescing identity: the `key`, else the canonical JSON (keys sorted)
  /// of `recover`.
  static String _identity(StacRecoveryInstruction instruction) {
    final key = instruction.key;
    if (key != null) return 'key:$key';
    return 'recover:${jsonEncode(_canonical(instruction.recover))}';
  }

  /// Safe to log: the key, or a hash of the canonical JSON.
  static String _label(StacRecoveryInstruction instruction, String identity) =>
      instruction.key != null
      ? 'key:${instruction.key}'
      : 'recover#${identity.hashCode.toRadixString(16)}';

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(value[k])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}
