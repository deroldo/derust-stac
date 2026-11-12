import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacResetStateActionParser
    extends StacActionParser<StacResetStateAction> {
  const StacResetStateActionParser();

  @override
  String get actionType => ActionType.resetState.name;

  @override
  StacResetStateAction getModel(Map<String, dynamic> json) =>
      StacResetStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacResetStateAction model) {
    final scope = StacScope.of(context);
    final keys = model.keys;
    if (keys == null) {
      StacStateScope.storeOf(context)?.resetAll();
      return null;
    }
    stacStateBatch(scope, keys, () {
      for (final k in keys) {
        scope.storeFor(k)?.reset(stacStateLocalKey(k));
      }
    });
    return null;
  }
}
