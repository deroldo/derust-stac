import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_reset_state.g.dart';

/// Restores state keys to their declared initial values. Without [keys], resets the whole screen state.
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacResetStateAction extends StacAction {
  /// Creates a [StacResetStateAction].
  const StacResetStateAction({this.keys});

  /// Keys to reset; null resets the entire screen state.
  final List<String>? keys;

  @override
  String get actionType => ActionType.resetState.name;

  /// Creates a [StacResetStateAction] from a JSON map.
  factory StacResetStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacResetStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacResetStateActionToJson(this);
}
