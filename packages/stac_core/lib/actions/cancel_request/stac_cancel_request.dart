import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_cancel_request.g.dart';

/// Cancels the in-flight [StacNetworkRequest] started with [requestKey] on
/// the current screen.
///
/// A cancelled request is discarded: none of its `onSuccess`, `onError` or
/// `onFinally` actions run. Does nothing if no such request is pending.
///
/// {@tool snippet}
/// JSON Example:
/// ```json
/// {
///   "actionType": "cancelRequest",
///   "requestKey": "search"
/// }
/// ```
/// {@end-tool}
@JsonSerializable()
class StacCancelRequest extends StacAction {
  /// Creates a [StacCancelRequest].
  const StacCancelRequest({required this.requestKey});

  /// The `requestKey` of the request to cancel.
  final String requestKey;

  @override
  String get actionType => ActionType.cancelRequest.name;

  /// Creates a [StacCancelRequest] from a JSON map.
  factory StacCancelRequest.fromJson(Map<String, dynamic> json) =>
      _$StacCancelRequestFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacCancelRequestToJson(this);
}
