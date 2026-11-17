import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_recovery_outcome.g.dart';

/// Result a server-driven recovery can report.
enum StacRecoveryOutcomeResult {
  /// The recovery worked; the request is repeated.
  success,

  /// The recovery failed; `onFailure` runs.
  failure,

  /// The recovery could not be done now; `onUnavailable` runs.
  unavailable,
}

/// Reports the result of the running recovery. Meant for the `recover`
/// actions of a recovery instruction; the first one emitted wins. Outside a
/// recovery it is logged and ignored.
///
/// Dart example:
/// ```dart
/// const StacRecoveryOutcome(result: StacRecoveryOutcomeResult.failure);
/// ```
///
/// JSON example:
/// ```json
/// { "actionType": "recoveryOutcome", "result": "failure" }
/// ```
@JsonSerializable()
class StacRecoveryOutcome extends StacAction {
  /// Creates a [StacRecoveryOutcome].
  const StacRecoveryOutcome({required this.result});

  /// The result of the recovery: `success`, `failure` or `unavailable`.
  final StacRecoveryOutcomeResult result;

  /// Action type identifier.
  @override
  String get actionType => ActionType.recoveryOutcome.name;

  /// Creates a `StacRecoveryOutcome` from JSON.
  factory StacRecoveryOutcome.fromJson(Map<String, dynamic> json) =>
      _$StacRecoveryOutcomeFromJson(json);

  /// Converts this action to JSON.
  @override
  Map<String, dynamic> toJson() => _$StacRecoveryOutcomeToJson(this);
}
