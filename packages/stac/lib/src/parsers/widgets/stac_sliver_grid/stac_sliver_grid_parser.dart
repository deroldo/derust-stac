import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/state/stac_item_template.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacSliverGridParser extends StacParser<StacSliverGrid> {
  const StacSliverGridParser();

  @override
  String get type => WidgetType.sliverGrid.name;

  @override
  StacSliverGrid getModel(Map<String, dynamic> json) =>
      StacSliverGrid.fromJson(json);

  @override
  Widget parse(BuildContext context, StacSliverGrid model) {
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: model.crossAxisCount ?? 1,
      mainAxisSpacing: model.mainAxisSpacing ?? 0.0,
      crossAxisSpacing: model.crossAxisSpacing ?? 0.0,
      childAspectRatio: model.childAspectRatio ?? 1.0,
      mainAxisExtent: model.mainAxisExtent,
    );

    final template = model.itemTemplate;
    if (StacItemTemplate.isActive(template)) {
      final items = StacItemTemplate.itemsOf(model.items, type);
      return SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => StacItemTemplate.build(
            template: template!,
            item: items[index],
            index: index,
            as: model.as,
            indexAs: model.indexAs,
          ),
          childCount: items.length,
          addAutomaticKeepAlives: model.addAutomaticKeepAlives ?? true,
          addRepaintBoundaries: model.addRepaintBoundaries ?? true,
          addSemanticIndexes: model.addSemanticIndexes ?? true,
        ),
        gridDelegate: gridDelegate,
      );
    }

    final children = model.children?.parseList(context) ?? const <Widget>[];

    return SliverGrid(
      delegate: SliverChildListDelegate(
        children,
        addAutomaticKeepAlives: model.addAutomaticKeepAlives ?? true,
        addRepaintBoundaries: model.addRepaintBoundaries ?? true,
        addSemanticIndexes: model.addSemanticIndexes ?? true,
      ),
      gridDelegate: gridDelegate,
    );
  }
}
