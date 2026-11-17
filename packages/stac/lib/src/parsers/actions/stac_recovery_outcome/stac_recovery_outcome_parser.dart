import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:stac/src/recovery/stac_recovery_exception.dart';
import 'package:stac/src/recovery/stac_recovery_run.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

/// Reports the result of the running recovery; a no-op (with a log) outside
/// one, including inside `onFailure` / `onUnavailable`.
class StacRecoveryOutcomeParser extends StacActionParser<StacRecoveryOutcome> {
  const StacRecoveryOutcomeParser();

  @override
  String get actionType => ActionType.recoveryOutcome.name;

  @override
  StacRecoveryOutcome getModel(Map<String, dynamic> json) =>
      StacRecoveryOutcome.fromJson(json);

  @override
  FutureOr onCall(BuildContext context, StacRecoveryOutcome model) {
    StacRecoveryRun.emitCurrent(switch (model.result) {
      StacRecoveryOutcomeResult.success => StacRecoveryResult.success,
      StacRecoveryOutcomeResult.failure => StacRecoveryResult.failure,
      StacRecoveryOutcomeResult.unavailable => StacRecoveryResult.unavailable,
    });
  }
}
