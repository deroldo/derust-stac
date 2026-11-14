import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

void main() {
  setUp(() => StacGlobalState.instance.clear());

  testWidgets('inner StacLocalScope shadows outer and sees outer', (t) async {
    late StacScope scope;
    await pumpStacWidget(
      t,
      StacLocalScope(
        vars: const {'item': 'outer', 'index': 1},
        child: StacLocalScope(
          vars: const {'item': 'inner'},
          child: Builder(
            builder: (c) {
              scope = StacScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(scope.lookup('item'), 'inner');
    expect(scope.lookup('index'), 1);
    expect(scope.lookup('missing'), isNull);
  });

  testWidgets('lookup reads screen keys and global view is live', (t) async {
    StacGlobalState.instance.store.declare('user', {'name': 'Ana'});
    late StacScope scope;
    await pumpStacWidget(
      t,
      StacStateScope(
        initialState: const {'total': 3},
        child: Builder(
          builder: (c) {
            scope = StacScope.of(c);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(scope.lookup('total'), 3);
    final view = scope.lookup('global');
    expect(view, isA<StacGlobalView>());
    expect(StacExpression.parse('global.user.name').evaluate(scope), 'Ana');
    StacGlobalState.instance.store.write('user', {'name': 'Bia'});
    expect(StacExpression.parse('global.user.name').evaluate(scope), 'Bia');
    expect(scope.write('total', 4), isTrue);
    expect(scope.lookup('total'), 4);
    expect(scope.write('global.user', {'name': 'Cy'}), isTrue);
    expect(scope.write('nope', 1), isFalse);
    expect(
      scope.listenablesFor({'total', 'global.user', 'item', 'x'}).length,
      2,
    );
  });

  testWidgets('action vars survive await inside runWithStacActionVars', (
    t,
  ) async {
    late BuildContext ctx;
    await pumpStacWidget(
      t,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    Object? before, after, nested;
    await runWithStacActionVars({'event': 'e1'}, () async {
      before = StacScope.of(ctx).lookup('event');
      await Future<void>.value();
      await Future<void>.microtask(() {});
      after = StacScope.of(ctx).lookup('event');
      await runWithStacActionVars({'result': 7}, () async {
        nested = [
          StacScope.of(ctx).lookup('event'),
          StacScope.of(ctx).lookup('result'),
        ];
      });
    });
    expect(before, 'e1');
    expect(after, 'e1');
    expect(nested, ['e1', 7]);
    expect(StacScope.of(ctx).lookup('event'), isNull);
  });

  testWidgets('screen store is disposed with the widget', (t) async {
    StacStateStore? store;
    await pumpStacWidget(
      t,
      StacStateScope(
        initialState: const {'a': 1},
        child: Builder(
          builder: (c) {
            store = StacStateScope.storeOf(c);
            return const SizedBox();
          },
        ),
      ),
    );
    final listenable = store!.listenable('a')!;
    var calls = 0;
    listenable.addListener(() => calls++);
    store!.write('a', 2);
    expect(calls, 1);
    await pumpStacWidget(t, const SizedBox());
    expect(store!.listenable('a'), isNull);
    expect(store!.has('a'), isFalse);
  });

  testWidgets('StacScope.of does not rebuild on state scope or local changes', (
    t,
  ) async {
    var builds = 0;
    final key = GlobalKey<_HostState>();
    // Same widget instance across host rebuilds: only an inherited
    // dependency could rebuild it.
    final probe = Builder(
      builder: (c) {
        builds++;
        StacScope.of(c);
        return const SizedBox();
      },
    );
    await pumpStacWidget(
      t,
      _Host(
        key: key,
        builder: (vars) => StacLocalScope(
          vars: vars,
          child: StacStateScope(initialState: const {'a': 1}, child: probe),
        ),
      ),
    );
    expect(builds, 1);
    key.currentState!.set({'item': 2});
    await t.pump();
    expect(builds, 1);
  });

  testWidgets('pumpStac renders through StacService.fromJson', (t) async {
    await pumpStac(t, {'type': 'text', 'data': 'hello'});
    expect(find.text('hello'), findsOneWidget);
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.builder, super.key});

  final Widget Function(Map<String, Object?> vars) builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Map<String, Object?> _vars = const {};

  void set(Map<String, Object?> v) => setState(() => _vars = v);

  @override
  Widget build(BuildContext context) => widget.builder(_vars);
}
