import 'package:stac/src/state/stac_scope.dart';
import 'package:stac/src/state/stac_state_store.dart';
import 'package:stac_logger/stac_logger.dart';

/// Key without the `global.` prefix, as stored by the target store.
String stacStateLocalKey(String path) =>
    path.startsWith('global.') ? path.substring(7) : path;

/// Reads the current value of [path] (`k` or `global.k`), `null` if absent.
Object? stacStateRead(StacScope scope, String path) {
  final store = scope.storeFor(path);
  return store?.read(stacStateLocalKey(path));
}

/// Runs [body] with notifications of the stores in [scope] deferred.
void stacStateBatch(StacScope scope, List<String> paths, void Function() body) {
  final stores = <StacStateStore>{
    for (final p in paths)
      if (scope.storeFor(p) != null) scope.storeFor(p)!,
  }.toList();
  void run(int i) {
    if (i == stores.length) {
      body();
    } else {
      stores[i].batch(() => run(i + 1));
    }
  }

  run(0);
}

num? stacStateNum(Object? v) => v is num ? v : null;

/// Shared implementation of incrementState/decrementState.
void stacStateStep(
  StacScope scope, {
  required String key,
  required Object? by,
  required Object? min,
  required Object? max,
  required int sign,
}) {
  final current = stacStateRead(scope, key);
  final step = by == null ? 1 : stacStateNum(by);
  if (current is! num || step == null) {
    Log.e('incrementState/decrementState on "$key": non-numeric value.');
    return;
  }
  num next = current + sign * step;
  final lo = stacStateNum(min);
  final hi = stacStateNum(max);
  if (lo != null && next < lo) next = lo;
  if (hi != null && next > hi) next = hi;
  scope.write(key, next);
}
