import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_append_state.g.dart';

/// Appends [value] to a list state key (writes a new list).
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacAppendStateAction extends StacAction {
  /// Creates a [StacAppendStateAction].
  const StacAppendStateAction({required this.key, this.value});

  /// State key holding a list.
  final String key;

  /// Value (or binding) to append.
  final Object? value;

  @override
  String get actionType => ActionType.appendState.name;

  /// Creates a [StacAppendStateAction] from a JSON map.
  factory StacAppendStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacAppendStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacAppendStateActionToJson(this);
}
