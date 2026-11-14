import 'package:material_ui/material_ui.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/src/utils/expression_resolver.dart';
import 'package:stac_core/stac_core.dart' hide StacBinding;
import 'package:stac_framework/stac_framework.dart';

class StacConditionalParser extends StacParser<StacConditional> {
  const StacConditionalParser();

  @override
  String get type => WidgetType.conditional.name;

  @override
  StacConditional getModel(Map<String, dynamic> json) =>
      StacConditional.fromJson(json);

  @override
  Widget parse(BuildContext context, StacConditional model) {
    // A binding is resolved to a value before getModel; a String keeps the
    // legacy expression syntax; anything else must be a bool (D6).
    final condition = model.condition;
    final result = condition is String
        ? ExpressionResolver.evaluate(condition)
        : StacBinding.strictBool(condition, 'condition');
    if (result == true) {
      return model.ifTrue.parse(context) ?? const SizedBox();
    } else if (model.ifFalse != null) {
      return model.ifFalse.parse(context) ?? const SizedBox();
    }
    return const SizedBox();
  }
}
