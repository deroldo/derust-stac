import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/stac.dart' hide StacBinding;

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

/// Widget stub that counts how many times it was parsed.
class _CountParser extends StacParser<Map<String, dynamic>> {
  const _CountParser();

  static int parses = 0;

  @override
  String get type => 'tplCount';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    parses++;
    return SizedBox(height: 40, child: Text('row:${model['label']}'));
  }
}

late StacStateStore _store;
late BuildContext _ctx;

Future<void> _pumpScreen(
  WidgetTester t,
  Map<String, dynamic> json, {
  Map<String, Object?> state = const {},
  ThemeData? theme,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: StacStateScope(
          initialState: state,
          child: Builder(
            builder: (c) {
              _ctx = c;
              _store = StacStateScope.storeOf(c)!;
              return StacService.fromJson(json, c)!;
            },
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Map<String, dynamic> _text(String expr) => {
  'type': 'text',
  'data': _expr(expr),
};

List<Map<String, Object?>> _todos(int n) => [
  for (var i = 0; i < n; i++) {'id': i, 'name': 'todo$i'},
];

void main() {
  setUpAll(() async {
    await initStacForTest();
    StacRegistry.instance.register(const _CountParser());
  });
  setUp(() {
    StacGlobalState.instance.clear();
    _CountParser.parses = 0;
  });

  group('listView', () {
    testWidgets('renders one item per entry of a state list', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('todos'),
          'itemTemplate': _text('item.name'),
        },
        state: {'todos': _todos(3)},
      );
      expect(find.text('todo0'), findsOneWidget);
      expect(find.text('todo1'), findsOneWidget);
      expect(find.text('todo2'), findsOneWidget);
    });

    testWidgets('appendState adds an item and a new list removes one', (
      t,
    ) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('todos'),
          'itemTemplate': _text('item.name'),
        },
        state: {'todos': _todos(2)},
      );
      await StacService.onCallFromJson({
        'actionType': 'appendState',
        'key': 'todos',
        'value': {'id': 9, 'name': 'extra'},
      }, _ctx);
      await t.pump();
      expect(find.text('extra'), findsOneWidget);
      expect(find.text('todo0'), findsOneWidget);

      await StacService.onCallFromJson({
        'actionType': 'setState',
        'values': {'todos': _todos(2).sublist(1)},
      }, _ctx);
      await t.pump();
      expect(find.text('todo0'), findsNothing);
      expect(find.text('todo1'), findsOneWidget);
      expect(find.text('extra'), findsNothing);
    });

    testWidgets('index and custom as/indexAs names', (t) async {
      await _pumpScreen(t, {
        'type': 'listView',
        'items': ['a', 'b'],
        'as': 'row',
        'indexAs': 'i',
        'itemTemplate': _text('(i + 1) + ". " + row'),
      });
      expect(find.text('1. a'), findsOneWidget);
      expect(find.text('2. b'), findsOneWidget);

      await _pumpScreen(t, {
        'type': 'listView',
        'items': ['x'],
        'itemTemplate': _text('index + ":" + item'),
      });
      expect(find.text('0:x'), findsOneWidget);
    });

    testWidgets('nested lists see both scopes', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('groups'),
          'as': 'pai',
          'itemTemplate': {
            'type': 'listView',
            'shrinkWrap': true,
            'items': _expr('pai.kids'),
            'as': 'filho',
            'itemTemplate': _text('pai.name + "/" + filho'),
          },
        },
        state: {
          'groups': [
            {
              'name': 'g1',
              'kids': ['a', 'b'],
            },
            {
              'name': 'g2',
              'kids': ['c'],
            },
          ],
        },
      );
      expect(find.text('g1/a'), findsOneWidget);
      expect(find.text('g1/b'), findsOneWidget);
      expect(find.text('g2/c'), findsOneWidget);
    });

    testWidgets('repeating a name shadows the outer one', (t) async {
      await _pumpScreen(t, {
        'type': 'listView',
        'items': [
          [1, 2],
        ],
        'itemTemplate': {
          'type': 'listView',
          'shrinkWrap': true,
          'items': _expr('item'),
          'itemTemplate': _text('"v" + item + "@" + index'),
        },
      });
      expect(find.text('v1@0'), findsOneWidget);
      expect(find.text('v2@1'), findsOneWidget);
    });

    testWidgets('a sibling with visible over length(list) == 0 shows empty', (
      t,
    ) async {
      await _pumpScreen(
        t,
        {
          'type': 'column',
          'children': [
            {
              'type': 'sizedBox',
              'height': 200,
              'child': {
                'type': 'listView',
                'items': _state('todos'),
                'itemTemplate': _text('item.name'),
              },
            },
            {
              'type': 'text',
              'data': 'empty',
              'visible': _expr('length(todos) == 0'),
            },
          ],
        },
        state: {'todos': <Object?>[]},
      );
      expect(find.text('empty'), findsOneWidget);
      _store.write('todos', _todos(1));
      await t.pump();
      expect(find.text('empty'), findsNothing);
      expect(find.text('todo0'), findsOneWidget);
    });

    testWidgets('items are built lazily', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('rows'),
          'itemTemplate': {'type': 'tplCount', 'label': _expr('item')},
        },
        state: {'rows': List<int>.generate(1000, (i) => i)},
      );
      expect(_CountParser.parses, greaterThan(0));
      expect(_CountParser.parses, lessThan(40));
      expect(find.text('row:0'), findsOneWidget);
      expect(find.text('row:999'), findsNothing);

      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pump();
      expect(_CountParser.parses, lessThan(200));
    });

    testWidgets('the template is not resolved by the parent (D2)', (t) async {
      final json = {
        'type': 'listView',
        'items': ['a'],
        'itemTemplate': _text('item'),
      };
      expect(StacBinding.hasBindings(json, isAction: false), isFalse);
      final bound = {...json, 'items': _state('x')};
      expect(StacBinding.hasBindings(bound, isAction: false), isTrue);
      expect(StacBinding.dependenciesOf(bound, isAction: false), {'x'});
    });

    testWidgets('actions inside the template see the item', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('todos'),
          'itemTemplate': {
            'type': 'textButton',
            'child': _text('item.name'),
            'onPressed': {
              'actionType': 'setState',
              'values': {'picked': _state('item.id')},
            },
          },
        },
        state: {'todos': _todos(3), 'picked': null},
      );
      await t.tap(find.text('todo2'));
      await t.pump();
      expect(_store.read('picked'), 2);
    });

    testWidgets('non-list or null items render nothing and do not crash', (
      t,
    ) async {
      await _pumpScreen(
        t,
        {
          'type': 'listView',
          'items': _state('x'),
          'itemTemplate': _text('item'),
        },
        state: {'x': 'oops'},
      );
      expect(find.byType(Text), findsNothing);
      _store.write('x', null);
      await t.pump();
      expect(find.byType(Text), findsNothing);
      _store.write('x', ['ok']);
      await t.pump();
      expect(find.text('ok'), findsOneWidget);
    });

    testWidgets('theme switch updates template items', (t) async {
      final json = {
        'type': 'listView',
        'items': ['a'],
        'itemTemplate': {
          'type': 'container',
          'height': 20,
          'color': 'primary',
          'child': _text('item'),
        },
      };
      Color? colorOf() =>
          t.widget<Container>(find.byType(Container).first).color ??
          (t.widget<Container>(find.byType(Container).first).decoration
                  as BoxDecoration?)
              ?.color;
      await _pumpScreen(
        t,
        json,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.red),
        ),
      );
      expect(colorOf(), Colors.red);
      await _pumpScreen(
        t,
        json,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.blue),
        ),
      );
      await t.pumpAndSettle();
      expect(colorOf(), Colors.blue);
    });

    testWidgets('legacy children and separator keep working', (t) async {
      await _pumpScreen(t, {
        'type': 'listView',
        'children': [
          {'type': 'text', 'data': 'one'},
          {'type': 'text', 'data': 'two'},
        ],
        'separator': {'type': 'divider'},
      });
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('with both, the template wins over children', (t) async {
      await _pumpScreen(t, {
        'type': 'listView',
        'items': ['a'],
        'itemTemplate': _text('item'),
        'children': [
          {'type': 'text', 'data': 'legacy'},
        ],
      });
      expect(find.text('a'), findsOneWidget);
      expect(find.text('legacy'), findsNothing);
    });

    testWidgets('separator is built between template items', (t) async {
      await _pumpScreen(t, {
        'type': 'listView',
        'items': ['a', 'b', 'c'],
        'itemTemplate': _text('item'),
        'separator': {'type': 'divider'},
      });
      expect(find.byType(Divider), findsNWidgets(2));
    });
  });

  group('gridView', () {
    testWidgets('renders template items, lazily', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'gridView',
          'crossAxisCount': 2,
          'items': _state('rows'),
          'itemTemplate': {'type': 'tplCount', 'label': _expr('item')},
        },
        state: {'rows': List<int>.generate(500, (i) => i)},
      );
      expect(find.text('row:0'), findsOneWidget);
      expect(find.text('row:499'), findsNothing);
      expect(_CountParser.parses, lessThan(60));
      _store.write('rows', [7]);
      await t.pump();
      expect(find.text('row:7'), findsOneWidget);
      expect(find.text('row:0'), findsNothing);
    });

    testWidgets('legacy children keep working', (t) async {
      await _pumpScreen(t, {
        'type': 'gridView',
        'crossAxisCount': 2,
        'children': [
          {'type': 'text', 'data': 'one'},
        ],
      });
      expect(find.text('one'), findsOneWidget);
    });
  });

  group('pageView', () {
    testWidgets('renders template pages and follows the list', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'pageView',
          'items': _state('pages'),
          'itemTemplate': _text('index + ":" + item'),
        },
        state: {
          'pages': ['p', 'q'],
        },
      );
      expect(find.text('0:p'), findsOneWidget);
      _store.write('pages', ['z']);
      await t.pump();
      expect(find.text('0:z'), findsOneWidget);
      expect(find.text('0:p'), findsNothing);
    });

    testWidgets('legacy children keep working', (t) async {
      await _pumpScreen(t, {
        'type': 'pageView',
        'children': [
          {'type': 'text', 'data': 'page1'},
        ],
      });
      expect(find.text('page1'), findsOneWidget);
    });
  });

  group('slivers', () {
    Map<String, dynamic> scroll(Map<String, dynamic> sliver) => {
      'type': 'customScrollView',
      'slivers': [sliver],
    };

    testWidgets('sliverList renders template items lazily', (t) async {
      await _pumpScreen(
        t,
        scroll({
          'type': 'sliverList',
          'items': _state('rows'),
          'itemTemplate': {'type': 'tplCount', 'label': _expr('item')},
        }),
        state: {'rows': List<int>.generate(1000, (i) => i)},
      );
      expect(find.text('row:0'), findsOneWidget);
      expect(find.text('row:999'), findsNothing);
      expect(_CountParser.parses, lessThan(40));
      _store.write('rows', [3, 4]);
      await t.pump();
      expect(find.text('row:3'), findsOneWidget);
      expect(find.text('row:4'), findsOneWidget);
    });

    testWidgets('sliverGrid renders template items lazily', (t) async {
      await _pumpScreen(
        t,
        scroll({
          'type': 'sliverGrid',
          'crossAxisCount': 2,
          'items': _state('rows'),
          'itemTemplate': {'type': 'tplCount', 'label': _expr('item')},
        }),
        state: {'rows': List<int>.generate(500, (i) => i)},
      );
      expect(find.text('row:0'), findsOneWidget);
      expect(find.text('row:499'), findsNothing);
      expect(_CountParser.parses, lessThan(60));
    });

    testWidgets('legacy children keep working', (t) async {
      await _pumpScreen(t, {
        'type': 'customScrollView',
        'slivers': [
          {
            'type': 'sliverList',
            'children': [
              {'type': 'text', 'data': 'a'},
            ],
          },
          {
            'type': 'sliverGrid',
            'crossAxisCount': 2,
            'children': [
              {'type': 'text', 'data': 'b'},
            ],
          },
        ],
      });
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });
  });

  group('model', () {
    test('new fields round-trip through JSON', () {
      final json = {
        'type': 'listView',
        'items': {r'$state': 'todos'},
        'as': 'todo',
        'indexAs': 'i',
        'itemTemplate': {'type': 'text', 'data': 'x'},
      };
      final model = StacListView.fromJson(json);
      expect(model.as, 'todo');
      expect(model.indexAs, 'i');
      expect(model.items, {r'$state': 'todos'});
      final out = model.toJson();
      expect(out['as'], 'todo');
      expect(out['indexAs'], 'i');
      expect(out['itemTemplate'], {'type': 'text', 'data': 'x'});
    });
  });
}
