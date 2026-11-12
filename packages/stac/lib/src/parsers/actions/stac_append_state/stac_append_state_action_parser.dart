import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';
import 'package:stac_logger/stac_logger.dart';

class StacAppendStateActionParser
    extends StacActionParser<StacAppendStateAction> {
  const StacAppendStateActionParser();

  @override
  String get actionType => ActionType.appendState.name;

  @override
  StacAppendStateAction getModel(Map<String, dynamic> json) =>
      StacAppendStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacAppendStateAction model) {
    final scope = StacScope.of(context);
    final current = stacStateRead(scope, model.key);
    if (current is! List) {
      Log.e("appendState on \"${model.key}\": value is not a list.");
      return null;
    }
    scope.write(model.key, [...current, model.value]);
    return null;
  }
}
