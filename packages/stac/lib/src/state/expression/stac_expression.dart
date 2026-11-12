import 'package:stac/src/state/expression/evaluator.dart';
import 'package:stac/src/state/expression/parser.dart';
import 'package:stac_logger/stac_logger.dart';

export 'package:stac/src/state/expression/evaluator.dart' show stacValuesEqual;

/// Resolves the root identifier of an expression (e.g. `total`, `global`,
/// `params`, `item`). Returns `null` when the name is unknown.
abstract class StacEvalContext {
  Object? lookup(String root);
}

/// Thrown by [StacExpression.parse] when the source is not valid syntax.
class StacExpressionException implements Exception {
  const StacExpressionException(this.message, [this.position]);

  final String message;
  final int? position;

  @override
  String toString() => position == null
      ? 'StacExpressionException: $message'
      : 'StacExpressionException: $message (at $position)';
}

/// A parsed state expression: a closed, side-effect free language evaluated
/// by a hand-written interpreter (never executes arbitrary code).
class StacExpression {
  StacExpression._(this.source, this._root)
    : dependencies = Set.unmodifiable(_collectDependencies(_root)),
      isPurePath = _isPurePath(_root);

  /// Parses [source]. Throws [StacExpressionException] on invalid syntax.
  static StacExpression parse(String source) {
    try {
      return StacExpression._(source, parseExpression(source));
    } on StacExpressionException {
      rethrow;
    } catch (e) {
      throw StacExpressionException('Invalid expression: $e');
    }
  }

  final String source;
  final StacNode _root;

  /// Top-level paths the expression reads: `total`, `global.usuario`. Includes
  /// branches that may not execute.
  final Set<String> dependencies;

  /// True when the expression is only an identifier/field/literal-index path.
  final bool isPurePath;

  /// Evaluates the expression. Never throws: an invalid operation yields
  /// `null` and a warning in the log.
  Object? evaluate(StacEvalContext ctx) {
    try {
      return evaluateNode(_root, ctx, source);
    } catch (e) {
      Log.w('Expression "$source" failed: $e');
      return null;
    }
  }

  @override
  String toString() => 'StacExpression($source)';
}

Set<String> _collectDependencies(StacNode node) {
  final result = <String>{};
  void visit(StacNode n) {
    switch (n) {
      case StacLiteral():
        break;
      case StacIdentifier():
        result.add(n.name);
      case StacFieldAccess():
        final path = _globalPath(n);
        if (path != null) {
          result.add(path);
        } else {
          visit(n.target);
        }
      case StacIndexAccess():
        visit(n.target);
        visit(n.index);
      case StacCall():
        n.args.forEach(visit);
      case StacUnary():
        visit(n.operand);
      case StacBinary():
        visit(n.left);
        visit(n.right);
      case StacTernary():
        visit(n.condition);
        visit(n.whenTrue);
        visit(n.whenFalse);
    }
  }

  visit(node);
  return result;
}

/// For `global.x[.y...]` returns `global.x`; otherwise `null`.
String? _globalPath(StacFieldAccess node) {
  // Walk down to the innermost field access whose target is `global`.
  StacNode current = node;
  String? key;
  while (current is StacFieldAccess) {
    final target = current.target;
    if (target is StacIdentifier && target.name == 'global') {
      key = current.field;
    }
    current = target;
  }
  if (current is StacIdentifier && current.name == 'global' && key != null) {
    return 'global.$key';
  }
  return null;
}

bool _isPurePath(StacNode node) {
  switch (node) {
    case StacIdentifier():
      return true;
    case StacFieldAccess():
      return _isPurePath(node.target);
    case StacIndexAccess():
      return node.index is StacLiteral && _isPurePath(node.target);
    default:
      return false;
  }
}
