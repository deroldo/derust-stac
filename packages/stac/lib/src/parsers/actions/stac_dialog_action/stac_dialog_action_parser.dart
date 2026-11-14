import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/parsers/foundation/interaction/stac_traversal_edge_behavior_parser.dart';
import 'package:stac/src/state/stac_pop_result.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac/src/utils/color_utils.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacDialogActionParser extends StacActionParser<StacDialogAction> {
  const StacDialogActionParser();

  @override
  String get actionType => ActionType.showDialog.name;

  @override
  StacDialogAction getModel(Map<String, dynamic> json) =>
      StacDialogAction.fromJson(json);

  @override
  FutureOr onCall(BuildContext context, StacDialogAction model) {
    if (model.widget != null) {
      return _showDialog(
        context,
        model,
        (c) => Stac.fromJson(model.widget, c) ?? const SizedBox(),
      );
    } else if (model.assetPath?.isNotEmpty ?? false) {
      final widget = Stac.fromAssets(model.assetPath!);
      return _showDialog(context, model, (_) => widget);
    } else if (model.request != null) {
      final widget = Stac.fromNetwork(
        context: context,
        request: model.request!,
      );
      return _showDialog(context, model, (_) => widget);
    }
  }

  Future _showDialog(
    BuildContext context,
    StacDialogAction model,
    WidgetBuilder content,
  ) {
    // The dialog lives under the Navigator, outside the screen: hand it the
    // screen's state and local variables so its bindings keep working.
    final reprovide = StacStateScope.reprovider(context);
    return showDialog(
      context: context,
      builder: (_) => reprovide(Builder(builder: content)),
      barrierDismissible: model.barrierDismissible ?? true,
      barrierColor: model.barrierColor.toColor(context),
      barrierLabel: model.barrierLabel,
      useSafeArea: model.useSafeArea ?? true,
      traversalEdgeBehavior: model.traversalEdgeBehavior?.parse,
    ).then(StacPopResult.unwrap);
  }
}
