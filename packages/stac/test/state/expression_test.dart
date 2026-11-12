import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/expression/stac_expression.dart';

class _Ctx implements StacEvalContext {
  _Ctx(this.values);

  final Map<String, Object?> values;

  @override
  Object? lookup(String root) => values[root];
}

Object? eval(String source, [Map<String, Object?> values = const {}]) =>
    StacExpression.parse(source).evaluate(_Ctx(values));

void main() {
  group('evaluate', () {
    final cases = <({String expr, Map<String, Object?> ctx, Object? expected})>[
      (expr: "'Total: ' + total", ctx: {'total': 3}, expected: 'Total: 3'),
      (expr: 'total == 10', ctx: {'total': 10}, expected: true),
      (expr: 'total == 10', ctx: {'total': 9}, expected: false),
      (expr: "total >= 10 ? 'max' : 'ok'", ctx: {'total': 10}, expected: 'max'),
      (expr: "total >= 10 ? 'max' : 'ok'", ctx: {'total': 1}, expected: 'ok'),
      (expr: 'null + 1', ctx: {}, expected: null),
      (expr: 'x + 1', ctx: {}, expected: null),
      (expr: '1 - null', ctx: {}, expected: null),
      (expr: '2 * true', ctx: {}, expected: null),
      (expr: '1 / 0', ctx: {}, expected: null),
      (expr: '1 % 0', ctx: {}, expected: null),
      (expr: '7 % 4', ctx: {}, expected: 3),
      (expr: "8 / 2", ctx: {}, expected: 4.0),
      (expr: "3 == '3'", ctx: {}, expected: false),
      (expr: "3 != '3'", ctx: {}, expected: true),
      (expr: 'x == null', ctx: {}, expected: true),
      (expr: 'x != null', ctx: {}, expected: false),
      (
        expr: 'lista[0].nome',
        ctx: {
          'lista': [
            {'nome': 'ana'},
          ],
        },
        expected: 'ana',
      ),
      (expr: 'lista[5].nome', ctx: {'lista': []}, expected: null),
      (
        expr: 'a.b.c',
        ctx: {
          'a': {'b': null},
        },
        expected: null,
      ),
      (expr: 'length(null) == 0', ctx: {}, expected: true),
      (expr: "length(trim('  ')) > 0", ctx: {}, expected: false),
      (expr: "length(trim(' ab ')) > 0", ctx: {}, expected: true),
      (
        expr: 'length(l)',
        ctx: {
          'l': [1, 2, 3],
        },
        expected: 3,
      ),
      (
        expr: "contains(sel, item, 'id')",
        ctx: {
          'sel': [
            {'id': 1, 'x': 'a'},
            {'id': 2},
          ],
          'item': {'id': 2, 'x': 'zzz'},
        },
        expected: true,
      ),
      (
        expr: "contains(sel, item, 'id')",
        ctx: {
          'sel': [
            {'id': 1},
          ],
          'item': {'id': 2},
        },
        expected: false,
      ),
      (
        expr: 'contains(l, 2)',
        ctx: {
          'l': [1, 2],
        },
        expected: true,
      ),
      (
        expr: 'contains(l, 3)',
        ctx: {
          'l': [1, 2],
        },
        expected: false,
      ),
      (expr: 'contains(null, 3)', ctx: {}, expected: false),
      (expr: 'false && (1 / 0 > 1)', ctx: {}, expected: false),
      (expr: 'true || (1 / 0 > 1)', ctx: {}, expected: true),
      (expr: 'true && false', ctx: {}, expected: false),
      (expr: 'false || true', ctx: {}, expected: true),
      (expr: '1 && true', ctx: {}, expected: null),
      (expr: '!true', ctx: {}, expected: false),
      (expr: '!1', ctx: {}, expected: null),
      (expr: '-total', ctx: {'total': 4}, expected: -4),
      (expr: "-'a'", ctx: {}, expected: null),
      (expr: '1 < null', ctx: {}, expected: null),
      (expr: "'a' < 'b'", ctx: {}, expected: null),
      (expr: '1 <= 1', ctx: {}, expected: true),
      (expr: '1 + 2 * 3 == 7', ctx: {}, expected: true),
      (expr: '(1 + 2) * 3', ctx: {}, expected: 9),
      (expr: '1 + 2 < 4 && 2 * 2 == 4', ctx: {}, expected: true),
      (expr: '1 || 2', ctx: {}, expected: null),
      (expr: '1.5 + 1.5', ctx: {}, expected: 3.0),
      (expr: "'x' + 3.0", ctx: {}, expected: 'x3'),
      (expr: "'x' + 3.5", ctx: {}, expected: 'x3.5'),
      (expr: "'x' + true", ctx: {}, expected: 'xtrue'),
      (expr: "'x' + null", ctx: {}, expected: null),
      (
        expr: "'x' + l",
        ctx: {
          'l': [1],
        },
        expected: null,
      ),
      (expr: "'a\\'b' + \"c\\\\d\"", ctx: {}, expected: "a'bc\\d"),
      (expr: 'c ? 1 : 2', ctx: {'c': 1}, expected: null),
      (expr: 'a ? 1 : b ? 2 : 3', ctx: {'a': false, 'b': true}, expected: 2),
      (
        expr: 'global.usuario.nome',
        ctx: {
          'global': {
            'usuario': {'nome': 'bia'},
          },
        },
        expected: 'bia',
      ),
    ];

    for (final c in cases) {
      test('${c.expr} with ${c.ctx}', () {
        final result = eval(c.expr, c.ctx);
        expect(result, c.expected);
        if (c.expected is double) expect(result, isA<double>());
        if (c.expected is int) expect(result, isA<int>());
      });
    }

    test('unevaluated ternary branch is not evaluated', () {
      expect(eval('true ? 1 : 1 / 0'), 1);
      expect(eval('false ? 1 / 0 : 2'), 2);
    });
  });

  group('dependencies and isPurePath', () {
    test('collects top-level paths', () {
      final e = StacExpression.parse(
        'global.usuario.nome == null && total > 1',
      );
      expect(e.dependencies, {'global.usuario', 'total'});
    });

    test('includes branches that are not executed', () {
      final e = StacExpression.parse('a ? b : c');
      expect(e.dependencies, {'a', 'b', 'c'});
    });

    test('ignores literals and function names, follows arguments', () {
      final e = StacExpression.parse("contains(sel, item, 'id') && true");
      expect(e.dependencies, {'sel', 'item'});
    });

    test('indexes in dependencies', () {
      final e = StacExpression.parse('lista[i].nome');
      expect(e.dependencies, {'lista', 'i'});
    });

    test('isPurePath', () {
      expect(StacExpression.parse('a').isPurePath, isTrue);
      expect(StacExpression.parse('a.b[0].c').isPurePath, isTrue);
      expect(StacExpression.parse('global.x').isPurePath, isTrue);
      expect(StacExpression.parse('a + 1').isPurePath, isFalse);
      expect(StacExpression.parse('1').isPurePath, isFalse);
      expect(StacExpression.parse('length(a)').isPurePath, isFalse);
      expect(StacExpression.parse('a[b]').isPurePath, isFalse);
    });
  });

  group('invalid syntax', () {
    for (final src in [
      '1 +',
      '',
      '(1',
      '1 2',
      'a.',
      'a[',
      "'abc",
      'a = 1',
      'a & b',
      'a ? b',
      'unknown(1)',
      'length()',
      'length(1, 2)',
      'contains(a)',
      '1 # 2',
    ]) {
      test('parse("$src") throws', () {
        expect(
          () => StacExpression.parse(src),
          throwsA(isA<StacExpressionException>()),
        );
      });
    }
  });

  test('evaluate never throws on random input', () {
    final rng = Random(42);
    const alphabet = "ab1 .+-*/%()[]!=<>&|?:,'\"\\length(contains(";
    final ctx = _Ctx({
      'a': 1,
      'b': [1, 2],
      'length': 'x',
    });
    for (var i = 0; i < 200; i++) {
      final src = String.fromCharCodes(
        List.generate(
          rng.nextInt(20),
          (_) => alphabet.codeUnitAt(rng.nextInt(alphabet.length)),
        ),
      );
      StacExpression expr;
      try {
        expr = StacExpression.parse(src);
      } on StacExpressionException {
        continue;
      }
      expect(() => expr.evaluate(ctx), returnsNormally, reason: src);
    }
  });
}
