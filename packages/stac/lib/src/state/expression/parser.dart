import 'package:stac/src/state/expression/functions.dart';
import 'package:stac/src/state/expression/lexer.dart';
import 'package:stac/src/state/expression/stac_expression.dart';

/// Immutable expression AST.
sealed class StacNode {
  const StacNode();
}

class StacLiteral extends StacNode {
  const StacLiteral(this.value);
  final Object? value;
}

class StacIdentifier extends StacNode {
  const StacIdentifier(this.name);
  final String name;
}

class StacFieldAccess extends StacNode {
  const StacFieldAccess(this.target, this.field);
  final StacNode target;
  final String field;
}

class StacIndexAccess extends StacNode {
  const StacIndexAccess(this.target, this.index);
  final StacNode target;
  final StacNode index;
}

class StacCall extends StacNode {
  const StacCall(this.name, this.args);
  final String name;
  final List<StacNode> args;
}

class StacUnary extends StacNode {
  const StacUnary(this.operator, this.operand);
  final StacTokenType operator;
  final StacNode operand;
}

class StacBinary extends StacNode {
  const StacBinary(this.operator, this.left, this.right);
  final StacTokenType operator;
  final StacNode left;
  final StacNode right;
}

class StacTernary extends StacNode {
  const StacTernary(this.condition, this.whenTrue, this.whenFalse);
  final StacNode condition;
  final StacNode whenTrue;
  final StacNode whenFalse;
}

/// Pratt parser. Precedence, lowest to highest: ternary, `||`, `&&`,
/// `== !=`, `< <= > >=`, `+ -`, `* / %`, unary `! -`, call/field/index.
StacNode parseExpression(String source) {
  final parser = _Parser(tokenize(source));
  final node = parser.parseTernary();
  parser.expectEnd();
  return node;
}

class _Parser {
  _Parser(this._tokens);

  final List<StacToken> _tokens;
  int _pos = 0;

  StacToken get _current => _tokens[_pos];

  bool _match(StacTokenType type) {
    if (_current.type != type) return false;
    _pos++;
    return true;
  }

  StacToken _expect(StacTokenType type, String what) {
    if (_current.type != type) {
      throw StacExpressionException(
        'Expected $what but found ${_current.type.name}',
        _current.position,
      );
    }
    return _tokens[_pos++];
  }

  void expectEnd() {
    if (_current.type != StacTokenType.end) {
      throw StacExpressionException(
        'Unexpected ${_current.type.name}',
        _current.position,
      );
    }
  }

  StacNode parseTernary() {
    final condition = _parseBinary(0);
    if (!_match(StacTokenType.question)) return condition;
    final whenTrue = parseTernary();
    _expect(StacTokenType.colon, '":"');
    final whenFalse = parseTernary();
    return StacTernary(condition, whenTrue, whenFalse);
  }

  static const List<List<StacTokenType>> _levels = [
    [StacTokenType.or],
    [StacTokenType.and],
    [StacTokenType.eq, StacTokenType.neq],
    [StacTokenType.lt, StacTokenType.lte, StacTokenType.gt, StacTokenType.gte],
    [StacTokenType.plus, StacTokenType.minus],
    [StacTokenType.star, StacTokenType.slash, StacTokenType.percent],
  ];

  StacNode _parseBinary(int level) {
    if (level >= _levels.length) return _parseUnary();
    var left = _parseBinary(level + 1);
    while (_levels[level].contains(_current.type)) {
      final operator = _tokens[_pos++].type;
      final right = _parseBinary(level + 1);
      left = StacBinary(operator, left, right);
    }
    return left;
  }

  StacNode _parseUnary() {
    if (_current.type == StacTokenType.bang ||
        _current.type == StacTokenType.minus) {
      final operator = _tokens[_pos++].type;
      return StacUnary(operator, _parseUnary());
    }
    return _parsePostfix();
  }

  StacNode _parsePostfix() {
    var node = _parsePrimary();
    while (true) {
      if (_match(StacTokenType.dot)) {
        final name = _expect(StacTokenType.identifier, 'a field name');
        node = StacFieldAccess(node, name.value! as String);
      } else if (_match(StacTokenType.leftBracket)) {
        final index = parseTernary();
        _expect(StacTokenType.rightBracket, '"]"');
        node = StacIndexAccess(node, index);
      } else {
        return node;
      }
    }
  }

  StacNode _parsePrimary() {
    final token = _current;
    switch (token.type) {
      case StacTokenType.number:
      case StacTokenType.string:
        _pos++;
        return StacLiteral(token.value);
      case StacTokenType.leftParen:
        _pos++;
        final inner = parseTernary();
        _expect(StacTokenType.rightParen, '")"');
        return inner;
      case StacTokenType.identifier:
        _pos++;
        final name = token.value! as String;
        if (_current.type == StacTokenType.leftParen) {
          return _parseCall(name, token.position);
        }
        return switch (name) {
          'true' => const StacLiteral(true),
          'false' => const StacLiteral(false),
          'null' => const StacLiteral(null),
          _ => StacIdentifier(name),
        };
      default:
        throw StacExpressionException(
          'Unexpected ${token.type.name}',
          token.position,
        );
    }
  }

  StacNode _parseCall(String name, int position) {
    final function = stacExpressionFunctions[name];
    if (function == null) {
      throw StacExpressionException('Unknown function "$name"', position);
    }
    _expect(StacTokenType.leftParen, '"("');
    final args = <StacNode>[];
    if (_current.type != StacTokenType.rightParen) {
      do {
        args.add(parseTernary());
      } while (_match(StacTokenType.comma));
    }
    _expect(StacTokenType.rightParen, '")"');
    if (args.length < function.minArgs || args.length > function.maxArgs) {
      throw StacExpressionException(
        'Wrong number of arguments for "$name"',
        position,
      );
    }
    return StacCall(name, args);
  }
}
