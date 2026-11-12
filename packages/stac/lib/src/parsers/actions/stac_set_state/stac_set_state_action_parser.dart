import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacSetStateActionParser extends StacActionParser<StacSetStateAction> {
  const StacSetStateActionParser();

  @override
  String get actionType => ActionType.setState.name;

  @override
  StacSetStateAction getModel(Map<String, dynamic> json) =>
      StacSetStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacSetStateAction model) {
    final scope = StacScope.of(context);
    stacStateBatch(scope, model.values.keys.toList(), () {
      for (final e in model.values.entries) {
        scope.write(e.key, e.value);
      }
    });
    return null;
  }
}
