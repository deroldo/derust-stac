import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacIncrementStateActionParser
    extends StacActionParser<StacIncrementStateAction> {
  const StacIncrementStateActionParser();

  @override
  String get actionType => ActionType.incrementState.name;

  @override
  StacIncrementStateAction getModel(Map<String, dynamic> json) =>
      StacIncrementStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(
    BuildContext context,
    StacIncrementStateAction model,
  ) {
    final scope = StacScope.of(context);
    stacStateBatch(scope, [model.key], () {
      stacStateStep(
        scope,
        key: model.key,
        by: model.by,
        min: model.min,
        max: model.max,
        sign: 1,
      );
    });
    return null;
  }
}
