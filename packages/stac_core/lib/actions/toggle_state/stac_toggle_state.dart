import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_toggle_state.g.dart';

/// Inverts a boolean state key.
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacToggleStateAction extends StacAction {
  /// Creates a [StacToggleStateAction].
  const StacToggleStateAction({required this.key});

  /// State key to toggle.
  final String key;

  @override
  String get actionType => ActionType.toggleState.name;

  /// Creates a [StacToggleStateAction] from a JSON map.
  factory StacToggleStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacToggleStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacToggleStateActionToJson(this);
}
