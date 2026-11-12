// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_navigate_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacNavigateAction _$StacNavigateActionFromJson(
  Map<String, dynamic> json,
) => StacNavigateAction(
  request: json['request'] == null
      ? null
      : StacNetworkRequest.fromJson(json['request'] as Map<String, dynamic>),
  widgetJson: json['widgetJson'] as Map<String, dynamic>?,
  assetPath: json['assetPath'] as String?,
  routeName: json['routeName'] as String?,
  navigationStyle: $enumDecodeNullable(
    _$NavigationStyleEnumMap,
    json['navigationStyle'],
  ),
  result: json['result'],
  hasResult:
      StacNavigateAction._readHasResult(json, 'hasResult') as bool? ?? false,
  arguments: json['arguments'] as Map<String, dynamic>?,
  params: json['params'] as Map<String, dynamic>?,
  onResult: json['onResult'] as Map<String, dynamic>?,
  onCancel: json['onCancel'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$StacNavigateActionToJson(StacNavigateAction instance) =>
    <String, dynamic>{
      'request': instance.request?.toJson(),
      'widgetJson': instance.widgetJson,
      'assetPath': instance.assetPath,
      'routeName': instance.routeName,
      'navigationStyle': _$NavigationStyleEnumMap[instance.navigationStyle],
      'result': instance.result,
      'arguments': instance.arguments,
      'params': instance.params,
      'onResult': instance.onResult,
      'onCancel': instance.onCancel,
      'actionType': instance.actionType,
    };

const _$NavigationStyleEnumMap = {
  NavigationStyle.push: 'push',
  NavigationStyle.pop: 'pop',
  NavigationStyle.pushReplacement: 'pushReplacement',
  NavigationStyle.pushAndRemoveAll: 'pushAndRemoveAll',
  NavigationStyle.popAll: 'popAll',
  NavigationStyle.pushNamed: 'pushNamed',
  NavigationStyle.pushNamedAndRemoveAll: 'pushNamedAndRemoveAll',
  NavigationStyle.pushReplacementNamed: 'pushReplacementNamed',
};
