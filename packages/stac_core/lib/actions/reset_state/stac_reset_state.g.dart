// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_reset_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacResetStateAction _$StacResetStateActionFromJson(
  Map<String, dynamic> json,
) => StacResetStateAction(
  keys: (json['keys'] as List<dynamic>?)?.map((e) => e as String).toList(),
);

Map<String, dynamic> _$StacResetStateActionToJson(
  StacResetStateAction instance,
) => <String, dynamic>{
  'keys': instance.keys,
  'actionType': instance.actionType,
};
