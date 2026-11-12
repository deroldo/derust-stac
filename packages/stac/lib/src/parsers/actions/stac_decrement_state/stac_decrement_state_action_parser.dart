import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacDecrementStateActionParser
    extends StacActionParser<StacDecrementStateAction> {
  const StacDecrementStateActionParser();

  @override
  String get actionType => ActionType.decrementState.name;

  @override
  StacDecrementStateAction getModel(Map<String, dynamic> json) =>
      StacDecrementStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(
    BuildContext context,
    StacDecrementStateAction model,
  ) {
    final scope = StacScope.of(context);
    stacStateBatch(scope, [model.key], () {
      stacStateStep(
        scope,
        key: model.key,
        by: model.by,
        min: model.min,
        max: model.max,
        sign: -1,
      );
    });
    return null;
  }
}
