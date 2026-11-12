// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_increment_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacIncrementStateAction _$StacIncrementStateActionFromJson(
  Map<String, dynamic> json,
) => StacIncrementStateAction(
  key: json['key'] as String,
  by: json['by'] ?? 1,
  min: json['min'],
  max: json['max'],
);

Map<String, dynamic> _$StacIncrementStateActionToJson(
  StacIncrementStateAction instance,
) => <String, dynamic>{
  'key': instance.key,
  'by': instance.by,
  'min': instance.min,
  'max': instance.max,
  'actionType': instance.actionType,
};
