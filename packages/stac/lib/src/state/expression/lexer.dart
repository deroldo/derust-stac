import 'package:stac/src/state/expression/stac_expression.dart';

enum StacTokenType {
  number,
  string,
  identifier,
  // Punctuation and operators.
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  comma,
  dot,
  question,
  colon,
  plus,
  minus,
  star,
  slash,
  percent,
  bang,
  eq,
  neq,
  lt,
  lte,
  gt,
  gte,
  and,
  or,
  end,
}

class StacToken {
  const StacToken(this.type, this.position, [this.value]);

  final StacTokenType type;
  final int position;

  /// `num` for numbers, `String` for strings and identifiers.
  final Object? value;

  @override
  String toString() => '$type${value != null ? '($value)' : ''}@$position';
}

/// Splits an expression source into tokens. Throws [StacExpressionException]
/// on unknown characters or unterminated strings.
List<StacToken> tokenize(String source) {
  final tokens = <StacToken>[];
  var i = 0;

  bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  bool isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x5f;

  while (i < source.length) {
    final c = source.codeUnitAt(i);
    final ch = source[i];

    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      i++;
      continue;
    }

    if (isDigit(c)) {
      final start = i;
      while (i < source.length && isDigit(source.codeUnitAt(i))) {
        i++;
      }
      var isDouble = false;
      if (i + 1 < source.length &&
          source[i] == '.' &&
          isDigit(source.codeUnitAt(i + 1))) {
        isDouble = true;
        i++;
        while (i < source.length && isDigit(source.codeUnitAt(i))) {
          i++;
        }
      }
      final text = source.substring(start, i);
      final num? value = isDouble ? double.tryParse(text) : int.tryParse(text);
      if (value == null) {
        throw StacExpressionException('Invalid number "$text"', start);
      }
      tokens.add(StacToken(StacTokenType.number, start, value));
      continue;
    }

    if (isIdentStart(c)) {
      final start = i;
      while (i < source.length &&
          (isIdentStart(source.codeUnitAt(i)) ||
              isDigit(source.codeUnitAt(i)))) {
        i++;
      }
      tokens.add(
        StacToken(StacTokenType.identifier, start, source.substring(start, i)),
      );
      continue;
    }

    if (ch == "'" || ch == '"') {
      final start = i;
      final buffer = StringBuffer();
      i++;
      var closed = false;
      while (i < source.length) {
        final current = source[i];
        if (current == '\\') {
          if (i + 1 >= source.length) break;
          final next = source[i + 1];
          buffer.write(switch (next) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            _ => next,
          });
          i += 2;
          continue;
        }
        if (current == ch) {
          closed = true;
          i++;
          break;
        }
        buffer.write(current);
        i++;
      }
      if (!closed) {
        throw StacExpressionException('Unterminated string', start);
      }
      tokens.add(StacToken(StacTokenType.string, start, buffer.toString()));
      continue;
    }

    final next = i + 1 < source.length ? source[i + 1] : '';
    StacTokenType? type;
    var length = 1;
    switch (ch) {
      case '(':
        type = StacTokenType.leftParen;
      case ')':
        type = StacTokenType.rightParen;
      case '[':
        type = StacTokenType.leftBracket;
      case ']':
        type = StacTokenType.rightBracket;
      case ',':
        type = StacTokenType.comma;
      case '.':
        type = StacTokenType.dot;
      case '?':
        type = StacTokenType.question;
      case ':':
        type = StacTokenType.colon;
      case '+':
        type = StacTokenType.plus;
      case '-':
        type = StacTokenType.minus;
      case '*':
        type = StacTokenType.star;
      case '/':
        type = StacTokenType.slash;
      case '%':
        type = StacTokenType.percent;
      case '!':
        if (next == '=') {
          type = StacTokenType.neq;
          length = 2;
        } else {
          type = StacTokenType.bang;
        }
      case '=':
        if (next == '=') {
          type = StacTokenType.eq;
          length = 2;
        }
      case '<':
        if (next == '=') {
          type = StacTokenType.lte;
          length = 2;
        } else {
          type = StacTokenType.lt;
        }
      case '>':
        if (next == '=') {
          type = StacTokenType.gte;
          length = 2;
        } else {
          type = StacTokenType.gt;
        }
      case '&':
        if (next == '&') {
          type = StacTokenType.and;
          length = 2;
        }
      case '|':
        if (next == '|') {
          type = StacTokenType.or;
          length = 2;
        }
    }

    if (type == null) {
      throw StacExpressionException('Unexpected character "$ch"', i);
    }
    tokens.add(StacToken(type, i));
    i += length;
  }

  tokens.add(StacToken(StacTokenType.end, source.length));
  return tokens;
}
