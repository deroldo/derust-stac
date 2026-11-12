import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/actions/stac_state_mutation/stac_state_mutation_utils.dart';
import 'package:stac/src/state/expression/stac_expression.dart'
    show stacValuesEqual;
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';
import 'package:stac_logger/stac_logger.dart';

class StacToggleItemActionParser
    extends StacActionParser<StacToggleItemAction> {
  const StacToggleItemActionParser();

  @override
  String get actionType => ActionType.toggleItem.name;

  @override
  StacToggleItemAction getModel(Map<String, dynamic> json) =>
      StacToggleItemAction.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacToggleItemAction model) {
    final scope = StacScope.of(context);
    final current = stacStateRead(scope, model.key);
    if (current is! List) {
      Log.e('toggleItem on "${model.key}": value is not a list.');
      return null;
    }
    final by = model.by;
    final value = model.value;
    Object? idOf(Object? v) => by != null && v is Map ? v[by] : v;
    final wanted = idOf(value);
    final at = current.indexWhere((e) => stacValuesEqual(idOf(e), wanted));
    if (at < 0) {
      scope.write(model.key, [...current, value]);
    } else {
      scope.write(model.key, [...current]..removeAt(at));
    }
    return null;
  }
}
