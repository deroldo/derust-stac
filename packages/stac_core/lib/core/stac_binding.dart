/// Helpers that build state bindings for the Dart DSL.
///
/// A binding serializes to `{"\$state": "key"}` or `{"\$expr": "expression"}`
/// and is resolved by the runtime.
class StacBinding {
  const StacBinding._();

  /// Binding to a state key or path, e.g. `StacBinding.state('user.name')`.
  static Map<String, String> state(String key) => {r'$state': key};

  /// Binding to an expression, e.g. `StacBinding.expr('a + 1')`.
  static Map<String, String> expr(String expression) => {r'$expr': expression};
}
