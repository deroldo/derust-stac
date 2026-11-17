import 'package:dio/dio.dart';
import 'package:stac/src/recovery/stac_error_envelope.dart';

/// `Response.extra` key under which the interceptor leaves the
/// [StacErrorEnvelope] it recognized in an error response.
const String stacEnvelopeExtraKey = 'stac.recovery.envelope';

/// The envelope recognized in the error response of [error], if any: the
/// final envelope of a [StacRecoveryException], or the one the recovery
/// interceptor attached to the response of a plain `DioException`.
StacErrorEnvelope? stacEnvelopeOf(Object? error) {
  if (error is StacRecoveryException) return error.envelope;
  if (error is DioException) {
    final value = error.response?.extra[stacEnvelopeExtraKey];
    if (value is StacErrorEnvelope) return value;
  }
  return null;
}

/// Outcome of a server-driven recovery (M6).
enum StacRecoveryResult { success, failure, unavailable }

/// What a request that went through a recovery attempt ends with when it
/// could not be resolved.
///
/// It is a `DioException` standing for the *last error observed* (M7): the
/// response of the repetition, or else the last failed request made by
/// `recover`, or else the original error. `response`, `type`, `error` ... are
/// those of [lastError], so callers that only know `DioException` keep
/// working.
class StacRecoveryException extends DioException {
  StacRecoveryException({
    required this.original,
    required this.lastError,
    required this.result,
    this.envelope,
    this.retried = false,
    this.onFailureRan = false,
    this.onUnavailableRan = false,
  }) : super(
         requestOptions: lastError.requestOptions,
         response: lastError.response,
         type: lastError.type,
         error: lastError.error,
         stackTrace: lastError.stackTrace,
         message: lastError.message,
       );

  /// The error that started the recovery.
  final DioException original;

  /// The last error observed (see the class comment).
  final DioException lastError;

  /// Result of the recovery run (`success` when only the repetition failed).
  final StacRecoveryResult result;

  /// Envelope of [lastError], when its response carried one.
  final StacErrorEnvelope? envelope;

  /// Whether the original request was sent again (and that repetition is
  /// [lastError]).
  final bool retried;

  /// Whether the instruction's `onFailure` ran (G6b: the caller does not
  /// render the final error then; it stays in `response` of its `onError`).
  final bool onFailureRan;

  /// Whether the instruction's `onUnavailable` ran.
  final bool onUnavailableRan;

  /// `onFailureRan || onUnavailableRan`.
  bool get hookRan => onFailureRan || onUnavailableRan;

  @override
  String toString() =>
      'StacRecoveryException(result: ${result.name}, retried: $retried, '
      'hookRan: $hookRan, last: ${lastError.type.name} '
      '${lastError.response?.statusCode ?? ''})';
}
