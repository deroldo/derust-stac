import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';

void main() {
  late StacMemoryStateStore store;

  setUp(() => store = StacMemoryStateStore());

  test('declare is idempotent and keeps current value', () {
    store.declare('a', 1);
    store.write('a', 5);
    store.declare('a', 9);
    expect(store.read('a'), 5);
    expect(store.initialOf('a'), 1);
  });

  test('write on undeclared key returns false without throwing', () {
    expect(store.write('nope', 1), isFalse);
    expect(store.has('nope'), isFalse);
    expect(store.read('nope'), isNull);
    expect(store.listenable('nope'), isNull);
  });

  test('write notifies listener once; equal scalar does not notify', () {
    store.declare('a', 1);
    var calls = 0;
    store.listenable('a')!.addListener(() => calls++);
    store.write('a', 2);
    expect(calls, 1);
    store.write('a', 2);
    expect(calls, 1);
  });

  test('batch with 3 writes notifies once per key', () {
    store.declare('a', 0);
    store.declare('b', 0);
    var a = 0, b = 0;
    store.listenable('a')!.addListener(() => a++);
    store.listenable('b')!.addListener(() => b++);
    store.batch(() {
      store.write('a', 1);
      store.write('a', 2);
      store.write('a', 3);
      store.write('b', 1);
      expect(a, 0);
      store.batch(() => store.write('b', 2));
      expect(b, 0);
    });
    expect(a, 1);
    expect(b, 1);
    expect(store.read('a'), 3);
    expect(store.read('b'), 2);
  });

  test('lists and maps are immutable deep copies', () {
    store.declare('l', <Object?>[]);
    final source = <Object?>[
      1,
      <String, Object?>{
        'x': [1],
      },
    ];
    store.write('l', source);
    source.add(3);
    (source[1] as Map<String, Object?>)['x'] = 0;
    final value = store.read('l') as List;
    expect(value.length, 2);
    expect(() => value.add(1), throwsUnsupportedError);
    final map = value[1] as Map;
    expect(() => map['y'] = 1, throwsUnsupportedError);
    expect(() => (map['x'] as List).add(1), throwsUnsupportedError);
    expect(map['x'], [1]);
  });

  test('replacing a collection with an equal one still notifies', () {
    store.declare('l', [1]);
    var calls = 0;
    store.listenable('l')!.addListener(() => calls++);
    store.write('l', [1]);
    expect(calls, 1);
  });

  test('reset and resetAll restore initial values', () {
    store.declare('a', 1);
    store.declare('b', [1]);
    store.write('a', 2);
    store.write('b', [1, 2]);
    store.reset('a');
    expect(store.read('a'), 1);
    expect(store.read('b'), [1, 2]);
    store.write('a', 3);
    store.resetAll();
    expect(store.read('a'), 1);
    expect(store.read('b'), [1]);
  });

  test('reserved names are rejected', () {
    for (final k in ['global', 'params', 'result', 'response', 'event']) {
      store.declare(k, 1);
      expect(store.has(k), isFalse);
      expect(store.write(k, 2), isFalse);
    }
  });

  test('StacGlobalState.instance shares value between readers', () {
    final g = StacGlobalState.instance;
    g.clear();
    g.store.declare('user', 'ana');
    g.store.write('user', 'bia');
    expect(StacGlobalState.instance.store.read('user'), 'bia');
    g.store.resetAll();
    expect(g.store.read('user'), 'ana');
    g.clear();
    expect(g.store.has('user'), isFalse);
  });
}
