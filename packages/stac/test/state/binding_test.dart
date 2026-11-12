import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/stac.dart' hide StacBinding;

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

void main() {
  setUpAll(() => initStacForTest());
  setUp(() => StacGlobalState.instance.clear());

  group('isBinding (D3)', () {
    test('accepts a single state or expr String key', () {
      expect(StacBinding.isBinding(_state('a')), isTrue);
      expect(StacBinding.isBinding(_expr('1 + 1')), isTrue);
    });

    test('rejects everything else', () {
      expect(StacBinding.isBinding(null), isFalse);
      expect(StacBinding.isBinding('a'), isFalse);
      expect(StacBinding.isBinding({r'$state': 1}), isFalse);
      expect(StacBinding.isBinding({r'$state': 'a', 'x': 1}), isFalse);
      expect(StacBinding.isBinding({r'$other': 'a'}), isFalse);
      expect(StacBinding.isBinding(<String, dynamic>{}), isFalse);
    });
  });

  group('hasBindings / dependenciesOf (D2)', () {
    final column = {
      'type': 'column',
      'children': [
        {'type': 'text', 'data': _state('a')},
      ],
    };

    test('a child widget is not part of the parent own JSON', () {
      expect(StacBinding.hasBindings(column, isAction: false), isFalse);
      expect(
        StacBinding.hasBindings(
          (column['children']! as List).first as Map<String, dynamic>,
          isAction: false,
        ),
        isTrue,
      );
    });

    test('plain sub-maps without type are walked', () {
      final json = {
        'type': 'text',
        'data': 'x',
        'style': {'fontSize': _state('size')},
        'list': [
          {'k': _expr('a + b')},
        ],
      };
      expect(StacBinding.hasBindings(json, isAction: false), isTrue);
      expect(StacBinding.dependenciesOf(json, isAction: false), {
        'size',
        'a',
        'b',
      });
    });

    test('nested actions are skipped for widgets and for actions', () {
      final widget = {
        'type': 'text',
        'onTap': {'actionType': 'x', 'v': _state('a')},
      };
      expect(StacBinding.hasBindings(widget, isAction: false), isFalse);
      final action = {
        'actionType': 'multiAction',
        'actions': [
          {'actionType': 'x', 'v': _state('a')},
        ],
      };
      expect(StacBinding.hasBindings(action, isAction: true), isFalse);
    });

    test('data keys of an action are scanned as a whole', () {
      final withWidgetLikeValue = {
        'actionType': 'setState',
        'values': {
          'w': {'type': 'text', 'data': _state('a')},
        },
      };
      expect(
        StacBinding.hasBindings(withWidgetLikeValue, isAction: true),
        isTrue,
      );
      // Same shape under a non-data key of an action: a child widget.
      final other = {
        'actionType': 'x',
        'content': {'type': 'text', 'data': _state('a')},
      };
      expect(StacBinding.hasBindings(other, isAction: true), isFalse);
    });

    test('foundation maps that carry a type are not mistaken for widgets', () {
      final json = {
        'type': 'container',
        'decoration': {
          'shape': {'type': 'circleBorder', 'side': _state('w')},
        },
      };
      expect(StacBinding.hasBindings(json, isAction: false), isTrue);
    });
  });

  group('resolve', () {
    testWidgets('replaces bindings deeply', (t) async {
      late StacScope scope;
      await pumpStacWidget(
        t,
        StacStateScope(
          initialState: const {'a': 5},
          child: Builder(
            builder: (c) {
              scope = StacScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      final resolved = StacBinding.resolve(
        {
          'n': _state('a'),
          'l': [_expr('1+1')],
          'keep': 'x',
        },
        scope,
        isAction: true,
      );
      expect(resolved, {
        'n': 5,
        'l': [2],
        'keep': 'x',
      });
    });

    testWidgets('widget: children and actions keep their identity (D2)', (
      t,
    ) async {
      late StacScope scope;
      await pumpStacWidget(
        t,
        StacStateScope(
          initialState: const {'a': 5},
          child: Builder(
            builder: (c) {
              scope = StacScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      final child = {'type': 'text', 'data': _state('a')};
      final action = {'actionType': 'x', 'v': _state('a')};
      final json = {
        'type': 'column',
        'width': _state('a'),
        'children': [child],
        'onTap': action,
      };
      final resolved =
          StacBinding.resolve(json, scope, isAction: false)
              as Map<String, dynamic>;
      expect(resolved['width'], 5);
      expect(identical((resolved['children'] as List).first, child), isTrue);
      expect(identical(resolved['onTap'], action), isTrue);
      // The input is never mutated.
      expect(json['width'], _state('a'));
    });

    testWidgets('action data keys resolve widget-like maps whole', (t) async {
      late StacScope scope;
      await pumpStacWidget(
        t,
        StacStateScope(
          initialState: const {'a': 'hi'},
          child: Builder(
            builder: (c) {
              scope = StacScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      final resolved =
          StacBinding.resolve(
                {
                  'actionType': 'setState',
                  'values': {
                    'w': {'type': 'text', 'data': _state('a')},
                  },
                  'onSuccess': [
                    {'actionType': 'x', 'v': _state('a')},
                  ],
                },
                scope,
                isAction: true,
              )
              as Map<String, dynamic>;
      expect(resolved['values'], {
        'w': {'type': 'text', 'data': 'hi'},
      });
      expect((resolved['onSuccess'] as List).first, {
        'actionType': 'x',
        'v': _state('a'),
      });
    });

    testWidgets('invalid bindings resolve to null', (t) async {
      late StacScope scope;
      await pumpStacWidget(
        t,
        StacStateScope(
          initialState: const {},
          child: Builder(
            builder: (c) {
              scope = StacScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      final resolved =
          StacBinding.resolve(
                {
                  'a': _expr('1 +'),
                  'b': _state('missing'),
                  'c': _state('1 + 1'),
                },
                scope,
                isAction: true,
              )
              as Map<String, dynamic>;
      expect(resolved, {'a': null, 'b': null, 'c': null});
    });
  });

  group('StacEnvelope', () {
    test('bind is rewritten to value binding + setState before onChanged', () {
      final json = StacEnvelope.rewriteBind({
        'type': 'checkBox',
        'bind': 'aceito',
        'onChanged': {'actionType': 'x'},
      }, 'checkBox');
      expect(json.containsKey('bind'), isFalse);
      expect(json['value'], _state('aceito'));
      expect(json['onChanged'], {
        'actionType': 'multiAction',
        'sync': true,
        'actions': [
          {
            'actionType': 'setState',
            'values': {'aceito': _state('event.value')},
          },
          {'actionType': 'x'},
        ],
      });
    });

    test('bind without onChanged only writes the state', () {
      final json = StacEnvelope.rewriteBind({
        'type': 'textField',
        'bind': 'q',
      }, 'textField');
      expect(json['initialValue'], _state('q'));
      expect((json['onChanged'] as Map)['actionType'], 'setState');
    });

    test('bind on an unsupported type is dropped', () {
      final json = StacEnvelope.rewriteBind({
        'type': 'text',
        'bind': 'q',
      }, 'text');
      expect(json, {'type': 'text'});
    });

    test('apply: visible false hides, true is stripped', () {
      expect(
        StacEnvelope.apply({'type': 'text', 'visible': false}, 'text'),
        isNull,
      );
      expect(
        StacEnvelope.apply({'type': 'text', 'visible': null}, 'text'),
        isNull,
      );
      expect(
        StacEnvelope.apply({'type': 'text', 'visible': 'yes'}, 'text'),
        isNull,
      );
      expect(StacEnvelope.apply({'type': 'text', 'visible': true}, 'text'), {
        'type': 'text',
      });
    });

    test('apply: visible is native on visibility', () {
      expect(
        StacEnvelope.apply({
          'type': 'visibility',
          'visible': null,
        }, 'visibility'),
        {'type': 'visibility', 'visible': false},
      );
    });

    test('apply: enabled is normalised and handed to the strategy', () {
      expect(
        StacEnvelope.apply({'type': 'textField', 'enabled': null}, 'textField'),
        {'type': 'textField', 'enabled': false},
      );
      StacEnvelope.disableStrategy['probe'] = (json, enabled) => {
        ...json,
        'strategy': enabled,
      };
      addTearDown(() => StacEnvelope.disableStrategy.remove('probe'));
      expect(StacEnvelope.apply({'type': 'probe', 'enabled': true}, 'probe'), {
        'type': 'probe',
        'enabled': true,
        'strategy': true,
      });
    });

    test('coerceResolved prints scalars as text', () {
      Object? data(Object? v) => StacEnvelope.coerceResolved({
        'type': 'text',
        'data': v,
      }, 'text')['data'];
      expect(data(null), '');
      expect(data(3), '3');
      expect(data(3.0), '3');
      expect(data(1.5), '1.5');
      expect(data(true), 'true');
      expect(data('x'), 'x');
    });
  });
}
