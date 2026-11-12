/// Marks a route result as "popped with a result" (D10).
///
/// A bare `null` from `Navigator.pop` (back button, gesture, `pop` without
/// `result`) is a cancellation; an explicit result, even `null`, is wrapped
/// here so the origin can tell the two apart.
class StacPopResult {
  const StacPopResult(this.value);

  final Object? value;

  /// The value a legacy caller expects: unwraps a [StacPopResult], leaves
  /// anything else untouched.
  static Object? unwrap(Object? routeResult) =>
      routeResult is StacPopResult ? routeResult.value : routeResult;
}
