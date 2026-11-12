import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_set_state.g.dart';

/// Writes several state keys at once (a single rebuild).
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacSetStateAction extends StacAction {
  /// Creates a [StacSetStateAction].
  const StacSetStateAction({required this.values});

  /// Map of state key to the value (or binding) to write.
  final Map<String, Object?> values;

  @override
  String get actionType => ActionType.setState.name;

  /// Creates a [StacSetStateAction] from a JSON map.
  factory StacSetStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacSetStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacSetStateActionToJson(this);
}
