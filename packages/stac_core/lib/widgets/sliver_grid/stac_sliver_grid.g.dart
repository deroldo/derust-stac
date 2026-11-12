// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_sliver_grid.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacSliverGrid _$StacSliverGridFromJson(
  Map<String, dynamic> json,
) => StacSliverGrid(
  crossAxisCount: (json['crossAxisCount'] as num?)?.toInt(),
  mainAxisSpacing: const DoubleConverter().fromJson(json['mainAxisSpacing']),
  crossAxisSpacing: const DoubleConverter().fromJson(json['crossAxisSpacing']),
  childAspectRatio: const DoubleConverter().fromJson(json['childAspectRatio']),
  mainAxisExtent: const DoubleConverter().fromJson(json['mainAxisExtent']),
  addAutomaticKeepAlives: json['addAutomaticKeepAlives'] as bool?,
  addRepaintBoundaries: json['addRepaintBoundaries'] as bool?,
  addSemanticIndexes: json['addSemanticIndexes'] as bool?,
  children: (json['children'] as List<dynamic>?)
      ?.map((e) => StacWidget.fromJson(e as Map<String, dynamic>))
      .toList(),
  items: json['items'],
  as: json['as'] as String?,
  indexAs: json['indexAs'] as String?,
  itemTemplate: json['itemTemplate'] == null
      ? null
      : StacWidget.fromJson(json['itemTemplate'] as Map<String, dynamic>),
);

Map<String, dynamic> _$StacSliverGridToJson(
  StacSliverGrid instance,
) => <String, dynamic>{
  'crossAxisCount': instance.crossAxisCount,
  'mainAxisSpacing': const DoubleConverter().toJson(instance.mainAxisSpacing),
  'crossAxisSpacing': const DoubleConverter().toJson(instance.crossAxisSpacing),
  'childAspectRatio': const DoubleConverter().toJson(instance.childAspectRatio),
  'mainAxisExtent': const DoubleConverter().toJson(instance.mainAxisExtent),
  'addAutomaticKeepAlives': instance.addAutomaticKeepAlives,
  'addRepaintBoundaries': instance.addRepaintBoundaries,
  'addSemanticIndexes': instance.addSemanticIndexes,
  'children': instance.children?.map((e) => e.toJson()).toList(),
  'items': instance.items,
  'as': instance.as,
  'indexAs': instance.indexAs,
  'itemTemplate': instance.itemTemplate?.toJson(),
  'type': instance.type,
};
