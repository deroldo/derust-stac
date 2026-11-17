// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_recovery_outcome.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacRecoveryOutcome _$StacRecoveryOutcomeFromJson(Map<String, dynamic> json) =>
    StacRecoveryOutcome(
      result: $enumDecode(_$StacRecoveryOutcomeResultEnumMap, json['result']),
    );

Map<String, dynamic> _$StacRecoveryOutcomeToJson(
  StacRecoveryOutcome instance,
) => <String, dynamic>{
  'result': _$StacRecoveryOutcomeResultEnumMap[instance.result]!,
  'actionType': instance.actionType,
};

const _$StacRecoveryOutcomeResultEnumMap = {
  StacRecoveryOutcomeResult.success: 'success',
  StacRecoveryOutcomeResult.failure: 'failure',
  StacRecoveryOutcomeResult.unavailable: 'unavailable',
};
