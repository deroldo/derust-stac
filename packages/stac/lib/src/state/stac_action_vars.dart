import 'dart:async';

const Symbol _actionVarsKey = #stacActionVars;

/// Variables (`event`, `result`, `response`, ...) of the action currently
/// running in this zone, or an empty map.
Map<String, Object?> currentStacActionVars() {
  final vars = Zone.current[_actionVarsKey];
  return vars is Map<String, Object?> ? vars : const {};
}

/// Runs [body] in a zone where [vars] are visible through `StacScope.of`,
/// including in async continuations. Nested calls merge with the outer vars
/// (inner ones shadow).
Future<T> runWithStacActionVars<T>(
  Map<String, Object?> vars,
  FutureOr<T> Function() body,
) {
  final merged = {...currentStacActionVars(), ...vars};
  return runZoned(
    () async => await body(),
    zoneValues: {_actionVarsKey: Map<String, Object?>.unmodifiable(merged)},
  );
}
