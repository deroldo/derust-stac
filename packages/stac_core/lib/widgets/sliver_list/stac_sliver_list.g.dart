// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_sliver_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacSliverList _$StacSliverListFromJson(Map<String, dynamic> json) =>
    StacSliverList(
      children: (json['children'] as List<dynamic>?)
          ?.map((e) => StacWidget.fromJson(e as Map<String, dynamic>))
          .toList(),
      items: json['items'],
      as: json['as'] as String?,
      indexAs: json['indexAs'] as String?,
      itemTemplate: json['itemTemplate'] == null
          ? null
          : StacWidget.fromJson(json['itemTemplate'] as Map<String, dynamic>),
      addAutomaticKeepAlives: json['addAutomaticKeepAlives'] as bool?,
      addRepaintBoundaries: json['addRepaintBoundaries'] as bool?,
      addSemanticIndexes: json['addSemanticIndexes'] as bool?,
      semanticIndexOffset: (json['semanticIndexOffset'] as num?)?.toInt(),
    );

Map<String, dynamic> _$StacSliverListToJson(StacSliverList instance) =>
    <String, dynamic>{
      'children': instance.children?.map((e) => e.toJson()).toList(),
      'addAutomaticKeepAlives': instance.addAutomaticKeepAlives,
      'addRepaintBoundaries': instance.addRepaintBoundaries,
      'addSemanticIndexes': instance.addSemanticIndexes,
      'semanticIndexOffset': instance.semanticIndexOffset,
      'items': instance.items,
      'as': instance.as,
      'indexAs': instance.indexAs,
      'itemTemplate': instance.itemTemplate?.toJson(),
      'type': instance.type,
    };
