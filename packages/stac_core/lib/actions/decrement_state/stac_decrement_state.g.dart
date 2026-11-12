// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_decrement_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacDecrementStateAction _$StacDecrementStateActionFromJson(
  Map<String, dynamic> json,
) => StacDecrementStateAction(
  key: json['key'] as String,
  by: json['by'] ?? 1,
  min: json['min'],
  max: json['max'],
);

Map<String, dynamic> _$StacDecrementStateActionToJson(
  StacDecrementStateAction instance,
) => <String, dynamic>{
  'key': instance.key,
  'by': instance.by,
  'min': instance.min,
  'max': instance.max,
  'actionType': instance.actionType,
};
