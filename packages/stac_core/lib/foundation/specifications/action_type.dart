/// Enumeration of all supported action types in the Stac framework.
///
/// The enum value's `.name` is typically used in JSON to reference the action
/// type when describing interactions and behaviors.
enum ActionType {
  /// Navigate to another route, page, or location.
  navigate,

  /// No operation; useful as a placeholder.
  none,

  /// Perform a network request (e.g., HTTP call).
  networkRequest,

  /// Display a modal bottom sheet.
  showModalBottomSheet,

  /// Display a dialog.
  showDialog,

  /// Retrieve a value from the current form state.
  getFormValue,

  /// Validate the current form state.
  validateForm,

  /// Show a transient message via a SnackBar.
  showSnackBar,

  /// Set or update a value in state.
  setValue,

  /// Execute multiple actions in sequence.
  multiAction,

  /// Wait for a specified duration before proceeding.
  delay,

  /// Write several state keys at once.
  setState,

  /// Increment a numeric state key.
  incrementState,

  /// Decrement a numeric state key.
  decrementState,

  /// Toggle a boolean state key.
  toggleState,

  /// Reset state keys to their initial values.
  resetState,

  /// Append a value to a list state key.
  appendState,

  /// Remove an item from a list state key by index or value.
  removeFromState,

  /// Add an item to a list state key, or remove it when present.
  toggleItem,

  /// Cancel an in-flight network request by its `requestKey`.
  cancelRequest,
}
