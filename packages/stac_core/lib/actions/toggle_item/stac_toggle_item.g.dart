// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_toggle_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacToggleItemAction _$StacToggleItemActionFromJson(
  Map<String, dynamic> json,
) => StacToggleItemAction(
  key: json['key'] as String,
  value: json['value'],
  by: json['by'] as String?,
);

Map<String, dynamic> _$StacToggleItemActionToJson(
  StacToggleItemAction instance,
) => <String, dynamic>{
  'key': instance.key,
  'value': instance.value,
  'by': instance.by,
  'actionType': instance.actionType,
};
