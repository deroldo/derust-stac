// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_remove_from_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacRemoveFromStateAction _$StacRemoveFromStateActionFromJson(
  Map<String, dynamic> json,
) => StacRemoveFromStateAction(
  key: json['key'] as String,
  index: json['index'],
  value: json['value'],
);

Map<String, dynamic> _$StacRemoveFromStateActionToJson(
  StacRemoveFromStateAction instance,
) => <String, dynamic>{
  'key': instance.key,
  'index': instance.index,
  'value': instance.value,
  'actionType': instance.actionType,
};
