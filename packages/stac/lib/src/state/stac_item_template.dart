import 'package:flutter/widgets.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart' hide StacBinding;
import 'package:stac_logger/stac_logger.dart';

/// Shared by listView, gridView, pageView, sliverList and sliverGrid: renders
/// one `itemTemplate` per entry of `items`.
///
/// `items` reaches the parser already resolved (the parent widget owns the
/// binding). The template is a child widget, so the parent never resolves it
/// (D2): each item resolves it against its own [StacLocalScope].
class StacItemTemplate {
  const StacItemTemplate._();

  static const String defaultItemName = 'item';
  static const String defaultIndexName = 'index';

  /// Whether the template path applies: `itemTemplate` wins over `children`.
  static bool isActive(StacWidget? itemTemplate) => itemTemplate != null;

  /// The items as a list. Anything that is not a list renders nothing (`null`
  /// is silent, other types are logged).
  static List<Object?> itemsOf(Object? items, String widgetType) {
    if (items is List) return items;
    if (items != null) {
      Log.w(
        '"items" of $widgetType must be a list, got $items; rendering none',
      );
    }
    return const [];
  }

  /// Builds item [index]: the template parsed in the context of the item's
  /// own element (CLAUDE.md: theme values resolve through that context), below
  /// a [StacLocalScope] holding the item and its index.
  static Widget build({
    required StacWidget template,
    required Object? item,
    required int index,
    String? as,
    String? indexAs,
    Widget fallback = const SizedBox.shrink(),
  }) {
    final itemName = _nameOr(as, defaultItemName);
    final indexName = _nameOr(indexAs, defaultIndexName);
    return StacLocalScope(
      vars: {itemName: item, indexName: index},
      child: Builder(builder: (context) => template.parse(context) ?? fallback),
    );
  }

  static String _nameOr(String? name, String fallback) =>
      name == null || name.isEmpty ? fallback : name;
}
