import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_remove_from_state.g.dart';

/// Removes one item from a list state key (writes a new list).
///
/// Removes the item at [index] or, when [index] is absent, the first item
/// deeply equal to [value]. Keys accept the `global.` prefix. Bindable fields
/// accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacRemoveFromStateAction extends StacAction {
  /// Creates a [StacRemoveFromStateAction].
  const StacRemoveFromStateAction({required this.key, this.index, this.value});

  /// State key holding a list.
  final String key;

  /// Index (or binding) of the item to remove.
  final Object? index;

  /// Value (or binding) of the item to remove (first occurrence).
  final Object? value;

  @override
  String get actionType => ActionType.removeFromState.name;

  /// Creates a [StacRemoveFromStateAction] from a JSON map.
  factory StacRemoveFromStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacRemoveFromStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacRemoveFromStateActionToJson(this);
}
