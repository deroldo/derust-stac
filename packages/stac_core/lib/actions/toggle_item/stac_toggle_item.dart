import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_toggle_item.g.dart';

/// Adds [value] to a list state key when absent, removes it when present.
///
/// When items are objects, [by] names the field that defines identity.
/// Keys accept the `global.` prefix. Bindable fields accept a
/// `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacToggleItemAction extends StacAction {
  /// Creates a [StacToggleItemAction].
  const StacToggleItemAction({required this.key, this.value, this.by});

  /// State key holding a list.
  final String key;

  /// Value (or binding) to toggle.
  final Object? value;

  /// Field name that defines identity when items are objects.
  final String? by;

  @override
  String get actionType => ActionType.toggleItem.name;

  /// Creates a [StacToggleItemAction] from a JSON map.
  factory StacToggleItemAction.fromJson(Map<String, dynamic> json) =>
      _$StacToggleItemActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacToggleItemActionToJson(this);
}
