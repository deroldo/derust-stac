import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_decrement_state.g.dart';

/// Subtracts [by] (default 1) from a numeric state key, clamped by [min]/[max].
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacDecrementStateAction extends StacAction {
  /// Creates a [StacDecrementStateAction].
  const StacDecrementStateAction({
    required this.key,
    this.by = 1,
    this.min,
    this.max,
  });

  /// State key to change.
  final String key;

  /// Step; defaults to 1.
  final Object? by;

  /// Lower bound (inclusive).
  final Object? min;

  /// Upper bound (inclusive).
  final Object? max;

  @override
  String get actionType => ActionType.decrementState.name;

  /// Creates a [StacDecrementStateAction] from a JSON map.
  factory StacDecrementStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacDecrementStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacDecrementStateActionToJson(this);
}
