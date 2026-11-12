import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/expression/stac_expression.dart'
    show stacValuesEqual;
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';
import 'package:stac_logger/stac_logger.dart';

class StacRemoveFromStateActionParser
    extends StacActionParser<StacRemoveFromStateAction> {
  const StacRemoveFromStateActionParser();

  @override
  String get actionType => ActionType.removeFromState.name;

  @override
  StacRemoveFromStateAction getModel(Map<String, dynamic> json) =>
      StacRemoveFromStateAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(
    BuildContext context,
    StacRemoveFromStateAction model,
  ) {
    final scope = StacScope.of(context);
    final current = stacStateRead(scope, model.key);
    if (current is! List) {
      Log.e('removeFromState on "${model.key}": value is not a list.');
      return null;
    }
    final index = model.index;
    if (index != null) {
      final i = index is num && index == index.truncate()
          ? index.toInt()
          : null;
      if (i == null || i < 0 || i >= current.length) {
        Log.w(
          'removeFromState on "${model.key}": index $index is out of range '
          '(length ${current.length}).',
        );
        return null;
      }
      scope.write(model.key, [...current]..removeAt(i));
      return null;
    }
    final at = current.indexWhere((e) => stacValuesEqual(e, model.value));
    if (at < 0) {
      Log.w('removeFromState on "${model.key}": value not found.');
      return null;
    }
    scope.write(model.key, [...current]..removeAt(at));
    return null;
  }
}
