import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';
import 'package:stac_logger/stac_logger.dart';

class StacToggleStateActionParser
    extends StacActionParser<StacToggleStateAction> {
  const StacToggleStateActionParser();

  @override
  String get actionType => ActionType.toggleState.name;

  @override
  StacToggleStateAction getModel(Map<String, dynamic> json) =>
      StacToggleStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacToggleStateAction model) {
    final scope = StacScope.of(context);
    final current = stacStateRead(scope, model.key);
    if (current is! bool) {
      Log.e("toggleState on \"${model.key}\": value is not a bool.");
      return null;
    }
    scope.write(model.key, !current);
    return null;
  }
}
