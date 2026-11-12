import 'package:stac/src/state/expression/evaluator.dart';
import 'package:stac_logger/stac_logger.dart';

/// Signature and implementation of a built-in expression function.
class StacExpressionFunction {
  const StacExpressionFunction(this.minArgs, this.maxArgs, this.call);

  final int minArgs;
  final int maxArgs;
  final Object? Function(List<Object?> args) call;
}

/// The closed set of functions available to expressions. Anything else is a
/// syntax error at parse time.
final Map<String, StacExpressionFunction> stacExpressionFunctions = {
  'length': StacExpressionFunction(1, 1, (args) {
    final value = args[0];
    if (value == null) return 0;
    if (value is String) return value.length;
    if (value is List) return value.length;
    Log.w('Expression: length() expects text or list, got ${_describe(value)}');
    return null;
  }),
  'trim': StacExpressionFunction(1, 1, (args) {
    final value = args[0];
    if (value == null) return '';
    if (value is String) return value.trim();
    Log.w('Expression: trim() expects text, got ${_describe(value)}');
    return null;
  }),
  'contains': StacExpressionFunction(2, 3, (args) {
    final list = args[0];
    if (list == null) return false;
    if (list is! List) {
      Log.w('Expression: contains() expects a list, got ${_describe(list)}');
      return null;
    }
    if (args.length == 2) {
      return list.any((element) => stacValuesEqual(element, args[1]));
    }
    final field = args[2];
    final target = args[1];
    if (field is! String) {
      Log.w('Expression: contains() field name must be text');
      return null;
    }
    if (target is! Map) {
      Log.w(
        'Expression: contains() expects an object, got ${_describe(target)}',
      );
      return null;
    }
    final wanted = target[field];
    return list.any(
      (element) => element is Map && stacValuesEqual(element[field], wanted),
    );
  }),
};

String _describe(Object? value) =>
    value == null ? 'null' : value.runtimeType.toString();
