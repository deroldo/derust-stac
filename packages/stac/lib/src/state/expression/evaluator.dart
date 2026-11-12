import 'package:stac/src/state/expression/functions.dart';
import 'package:stac/src/state/expression/lexer.dart';
import 'package:stac/src/state/expression/parser.dart';
import 'package:stac/src/state/expression/stac_expression.dart';
import 'package:stac_logger/stac_logger.dart';

/// Equality without coercion: `3 != "3"`. Lists and maps compare deeply.
bool stacValuesEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!stacValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !stacValuesEqual(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// Pure evaluator over the AST. Never throws: any failure logs and yields
/// `null`.
Object? evaluateNode(StacNode node, StacEvalContext ctx, String source) {
  try {
    return _Evaluator(ctx, source).eval(node);
  } catch (e) {
    Log.w('Expression "$source" failed: $e');
    return null;
  }
}

class _Evaluator {
  _Evaluator(this.ctx, this.source);

  final StacEvalContext ctx;
  final String source;

  Object? _invalid(String reason) {
    Log.w('Expression "$source": $reason');
    return null;
  }

  Object? eval(StacNode node) {
    switch (node) {
      case StacLiteral():
        return node.value;
      case StacIdentifier():
        return ctx.lookup(node.name);
      case StacFieldAccess():
        final target = eval(node.target);
        if (target is Map) return target[node.field];
        return null;
      case StacIndexAccess():
        final target = eval(node.target);
        final index = eval(node.index);
        if (target is List && index is int) {
          return index >= 0 && index < target.length ? target[index] : null;
        }
        if (target is Map && index is String) return target[index];
        return null;
      case StacCall():
        final function = stacExpressionFunctions[node.name]!;
        return function.call([for (final a in node.args) eval(a)]);
      case StacUnary():
        return _unary(node);
      case StacBinary():
        return _binary(node);
      case StacTernary():
        final condition = eval(node.condition);
        if (condition is! bool) {
          return _invalid('ternary condition is not a boolean');
        }
        return eval(condition ? node.whenTrue : node.whenFalse);
    }
  }

  Object? _unary(StacUnary node) {
    final value = eval(node.operand);
    if (node.operator == StacTokenType.bang) {
      if (value is! bool) return _invalid('"!" expects a boolean');
      return !value;
    }
    if (value is! num) return _invalid('unary "-" expects a number');
    return -value;
  }

  Object? _binary(StacBinary node) {
    final op = node.operator;

    if (op == StacTokenType.and || op == StacTokenType.or) {
      final left = eval(node.left);
      if (left is! bool) return _invalid('logical operator expects booleans');
      if (op == StacTokenType.and && !left) return false;
      if (op == StacTokenType.or && left) return true;
      final right = eval(node.right);
      if (right is! bool) return _invalid('logical operator expects booleans');
      return right;
    }

    final left = eval(node.left);
    final right = eval(node.right);

    switch (op) {
      case StacTokenType.eq:
        return stacValuesEqual(left, right);
      case StacTokenType.neq:
        return !stacValuesEqual(left, right);
      case StacTokenType.lt:
      case StacTokenType.lte:
      case StacTokenType.gt:
      case StacTokenType.gte:
        if (left is! num || right is! num) {
          return _invalid('comparison expects numbers');
        }
        return switch (op) {
          StacTokenType.lt => left < right,
          StacTokenType.lte => left <= right,
          StacTokenType.gt => left > right,
          _ => left >= right,
        };
      case StacTokenType.plus:
        if (left is String || right is String) {
          final l = _concatOperand(left);
          final r = _concatOperand(right);
          if (l == null || r == null) {
            return _invalid('invalid operand for text concatenation');
          }
          return l + r;
        }
        if (left is num && right is num) return left + right;
        return _invalid('"+" expects numbers or text');
      case StacTokenType.minus:
      case StacTokenType.star:
      case StacTokenType.slash:
      case StacTokenType.percent:
        if (left is! num || right is! num) {
          return _invalid('arithmetic expects numbers');
        }
        switch (op) {
          case StacTokenType.minus:
            return left - right;
          case StacTokenType.star:
            return left * right;
          case StacTokenType.slash:
            if (right == 0) return _invalid('division by zero');
            return left / right;
          default:
            if (right == 0) return _invalid('modulo by zero');
            return left % right;
        }
      default:
        return _invalid('unsupported operator ${op.name}');
    }
  }

  /// Text form of a concatenation operand, or `null` when it is not allowed.
  String? _concatOperand(Object? value) {
    if (value is String) return value;
    if (value is bool) return value.toString();
    if (value is num) {
      if (value is double &&
          value.isFinite &&
          value == value.truncateToDouble()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    return null;
  }
}
