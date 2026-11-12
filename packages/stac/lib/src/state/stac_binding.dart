import 'package:stac/src/framework/stac_registry.dart';
import 'package:stac/src/state/expression/stac_expression.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_logger/stac_logger.dart';

const String _stateKey = r'$state';
const String _exprKey = r'$expr';

/// Action keys that hold plain data (D2): resolved as a whole, with no
/// "skip children" rule, because they carry values and not widgets/actions.
const Set<String> stacActionDataKeys = {
  'values',
  'value',
  'result',
  'params',
  'body',
  'queryParameters',
  'headers',
  'initial',
};

/// Detection and resolution of `{"$state": ...}` / `{"$expr": ...}` bindings
/// in the JSON of a single widget or action.
///
/// D2: when walking the JSON that belongs to a widget, a sub-map is skipped
/// (left untouched, same instance) if it is an action (`actionType`) or a
/// child widget (`type` registered in [StacRegistry]); those resolve
/// themselves when they are rendered/executed.
class StacBinding {
  const StacBinding._();

  /// D3: a map with exactly one key, `$state` or `$expr`, whose value is a
  /// String.
  static bool isBinding(Object? value) {
    if (value is! Map || value.length != 1) return false;
    return value[_stateKey] is String || value[_exprKey] is String;
  }

  /// Whether the own JSON of a widget/action (children and nested actions
  /// excluded, D2) contains any binding.
  static bool hasBindings(Map<String, dynamic> json, {required bool isAction}) {
    var found = false;
    _visit(json, isAction, (_) => found = true, () => found);
    return found;
  }

  /// Top-level dependencies (D5) of every binding in the own JSON.
  static Set<String> dependenciesOf(
    Map<String, dynamic> json, {
    required bool isAction,
  }) {
    final result = <String>{};
    _visit(json, isAction, (binding) {
      final expression = _expressionOf(binding);
      if (expression != null) result.addAll(expression.dependencies);
    }, () => false);
    return result;
  }

  /// Copy of [json] with bindings replaced by their values. Sub-maps skipped
  /// by D2 keep their identity. Unchanged branches are returned as is.
  static dynamic resolve(
    dynamic json,
    StacScope scope, {
    required bool isAction,
  }) {
    if (json is! Map<String, dynamic>) {
      return _resolveValue(json, scope, deep: false);
    }
    Map<String, dynamic>? copy;
    for (final entry in json.entries) {
      final resolved = _resolveValue(
        entry.value,
        scope,
        deep: isAction && stacActionDataKeys.contains(entry.key),
      );
      if (!identical(resolved, entry.value)) {
        copy ??= Map<String, dynamic>.of(json);
        copy[entry.key] = resolved;
      }
    }
    return copy ?? json;
  }

  /// Evaluates one binding map.
  static Object? evaluate(Map<dynamic, dynamic> binding, StacScope scope) {
    final expression = _expressionOf(binding);
    if (expression == null) return null;
    if (binding.containsKey(_stateKey) && !expression.isPurePath) {
      Log.w(
        '\$state "${binding[_stateKey]}" is not a plain path; '
        'use \$expr for expressions',
      );
      return null;
    }
    return expression.evaluate(scope);
  }

  /// Strict boolean for `visible`, `enabled` and `condition` (D6): anything
  /// that is not a bool (invalid expression, missing key, error) is `false`.
  static bool asBool(Object? value, StacScope scope, String what) {
    return strictBool(
      isBinding(value) ? evaluate(value! as Map, scope) : value,
      what,
    );
  }

  /// D6 for an already resolved [value]: only a real bool counts as `true`.
  static bool strictBool(Object? value, String what) {
    if (value is bool) return value;
    Log.w(
      StacGlobalState.instance.redact(
        '"$what" must evaluate to a bool, got $value; treating as false',
      ),
    );
    return false;
  }

  // -- internals -----------------------------------------------------------

  /// D2: actions and registered widgets are not part of the own JSON.
  static bool _isChild(Map<dynamic, dynamic> map) {
    if (map['actionType'] is String) return true;
    final type = map['type'];
    return type is String && StacRegistry.instance.getParser(type) != null;
  }

  static void _visit(
    Map<String, dynamic> json,
    bool isAction,
    void Function(Map<dynamic, dynamic> binding) onBinding,
    bool Function() stop,
  ) {
    void walk(Object? value, bool deep) {
      if (stop()) return;
      if (value is Map) {
        if (isBinding(value)) {
          onBinding(value);
        } else if (deep || !_isChild(value)) {
          for (final v in value.values) {
            walk(v, deep);
          }
        }
      } else if (value is List) {
        for (final v in value) {
          walk(v, deep);
        }
      }
    }

    for (final entry in json.entries) {
      walk(entry.value, isAction && stacActionDataKeys.contains(entry.key));
      if (stop()) return;
    }
  }

  static dynamic _resolveValue(
    dynamic value,
    StacScope scope, {
    required bool deep,
  }) {
    if (value is Map) {
      if (isBinding(value)) return evaluate(value, scope);
      if (!deep && _isChild(value)) return value;
      Map<dynamic, dynamic>? copy;
      for (final entry in value.entries) {
        final resolved = _resolveValue(entry.value, scope, deep: deep);
        if (!identical(resolved, entry.value)) {
          copy ??= Map<dynamic, dynamic>.of(value);
          copy[entry.key] = resolved;
        }
      }
      if (copy == null) return value;
      return value is Map<String, dynamic>
          ? Map<String, dynamic>.from(copy)
          : copy;
    }
    if (value is List) {
      List<dynamic>? copy;
      for (var i = 0; i < value.length; i++) {
        final resolved = _resolveValue(value[i], scope, deep: deep);
        if (!identical(resolved, value[i])) {
          copy ??= List<dynamic>.of(value);
          copy[i] = resolved;
        }
      }
      return copy ?? value;
    }
    return value;
  }

  static const int _cacheLimit = 512;
  static final Map<String, StacExpression?> _cache = {};

  static StacExpression? _expressionOf(Map<dynamic, dynamic> binding) {
    final source = (binding[_stateKey] ?? binding[_exprKey]) as String;
    if (_cache.containsKey(source)) return _cache[source];
    StacExpression? parsed;
    try {
      parsed = StacExpression.parse(source);
    } on StacExpressionException catch (e) {
      Log.w('Invalid binding "$source": ${e.message}');
    }
    if (_cache.length >= _cacheLimit) _cache.clear();
    return _cache[source] = parsed;
  }
}
