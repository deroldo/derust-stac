import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/parsers/foundation/borders/stac_border_parser.dart';
import 'package:stac/src/parsers/foundation/geometry/stac_box_constraints_parser.dart';
import 'package:stac/src/state/stac_pop_result.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac/src/utils/color_utils.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacModalBottomSheetActionParser
    extends StacActionParser<StacModalBottomSheetAction> {
  const StacModalBottomSheetActionParser();

  @override
  String get actionType => ActionType.showModalBottomSheet.name;

  @override
  StacModalBottomSheetAction getModel(Map<String, dynamic> json) =>
      StacModalBottomSheetAction.fromJson(json);

  @override
  FutureOr onCall(BuildContext context, model) {
    if (model.widget != null) {
      return _showModalBottomSheet(
        context,
        model,
        (c) => model.widget?.parse(c) ?? const SizedBox(),
      );
    } else if (model.assetPath?.isNotEmpty ?? false) {
      final widget = Stac.fromAssets(model.assetPath!);
      return _showModalBottomSheet(context, model, (_) => widget);
    } else if (model.request != null) {
      final widget = Stac.fromNetwork(
        context: context,
        request: model.request!,
      );
      return _showModalBottomSheet(context, model, (_) => widget);
    }
  }

  Future _showModalBottomSheet(
    BuildContext context,
    StacModalBottomSheetAction model,
    WidgetBuilder content,
  ) {
    // The sheet lives under the Navigator, outside the screen: hand it the
    // screen's state and local variables so its bindings keep working.
    final reprovide = StacStateScope.reprovider(context);
    return showModalBottomSheet(
      context: context,
      builder: (_) => reprovide(Builder(builder: content)),
      backgroundColor: model.backgroundColor.toColor(context),
      barrierLabel: model.barrierLabel,
      elevation: model.elevation,
      shape: model.shape?.parse(context),
      constraints: model.constraints?.parse,
      barrierColor: model.barrierColor.toColor(context),
      isScrollControlled: model.isScrollControlled ?? false,
      useRootNavigator: model.useRootNavigator ?? false,
      isDismissible: model.isDismissible ?? true,
      enableDrag: model.enableDrag ?? true,
      showDragHandle: model.showDragHandle,
      useSafeArea: model.useSafeArea ?? false,
    ).then(StacPopResult.unwrap);
  }
}
