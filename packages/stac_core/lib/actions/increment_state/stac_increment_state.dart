import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_action.dart';
import 'package:stac_core/foundation/specifications/action_type.dart';

part 'stac_increment_state.g.dart';

/// Adds [by] (default 1) to a numeric state key, clamped by [min]/[max].
///
/// Keys accept the `global.` prefix to address the global state. Bindable
/// fields accept a `StacBinding.state(...)` / `StacBinding.expr(...)`.
@JsonSerializable()
class StacIncrementStateAction extends StacAction {
  /// Creates a [StacIncrementStateAction].
  const StacIncrementStateAction({
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
  String get actionType => ActionType.incrementState.name;

  /// Creates a [StacIncrementStateAction] from a JSON map.
  factory StacIncrementStateAction.fromJson(Map<String, dynamic> json) =>
      _$StacIncrementStateActionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacIncrementStateActionToJson(this);
}
