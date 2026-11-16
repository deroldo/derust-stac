/// Recovery instruction carried by a server error envelope (`recovery`).
///
/// `recover`, `onFailure` and `onUnavailable` are kept as raw JSON (a Stac
/// action map or a list of them); they are executed by the runtime later.
class StacRecoveryInstruction {
  const StacRecoveryInstruction({
    required this.recover,
    this.key,
    this.keyDisabled = false,
    this.retry,
    this.onFailure,
    this.onUnavailable,
    this.timeoutMs,
  });

  /// Coalescing key. `null` with [keyDisabled] false means "absent" (the
  /// default key is derived from [recover]).
  final String? key;

  /// `true` when `key` was present and explicitly `null` (coalescing off).
  final bool keyDisabled;

  /// Action (`Map`) or list of actions (`List`), raw JSON.
  final Object recover;

  final StacRetryInstruction? retry;

  /// Action (`Map`) or list of actions (`List`), raw JSON.
  final Object? onFailure;

  /// Action (`Map`) or list of actions (`List`), raw JSON.
  final Object? onUnavailable;

  final int? timeoutMs;

  /// Parses [json]; throws [FormatException] when malformed.
  factory StacRecoveryInstruction.fromJson(Map<String, dynamic> json) {
    final recover = json['recover'];
    if (!_isActionOrList(recover)) {
      throw const FormatException('recovery.recover must be an action or list');
    }
    final onFailure = json['onFailure'];
    if (onFailure != null && !_isActionOrList(onFailure)) {
      throw const FormatException('recovery.onFailure must be action or list');
    }
    final onUnavailable = json['onUnavailable'];
    if (onUnavailable != null && !_isActionOrList(onUnavailable)) {
      throw const FormatException(
        'recovery.onUnavailable must be action or list',
      );
    }
    final key = json['key'];
    if (key != null && key is! String) {
      throw const FormatException('recovery.key must be a string or null');
    }
    final timeout = json['timeoutMs'];
    if (timeout != null && timeout is! int) {
      throw const FormatException('recovery.timeoutMs must be an int');
    }
    final retry = json['retry'];
    if (retry != null && retry is! Map) {
      throw const FormatException('recovery.retry must be an object');
    }
    return StacRecoveryInstruction(
      key: key as String?,
      keyDisabled: json.containsKey('key') && key == null,
      recover: recover!,
      retry: retry == null
          ? null
          : StacRetryInstruction.fromJson(
              Map<String, dynamic>.from(retry as Map),
            ),
      onFailure: onFailure,
      onUnavailable: onUnavailable,
      timeoutMs: timeout as int?,
    );
  }

  static bool _isActionOrList(Object? v) => v is Map || v is List;
}

/// `recovery.retry`: how the original request is changed on its single retry.
class StacRetryInstruction {
  const StacRetryInstruction({
    this.headers,
    this.queryParameters,
    this.body,
    this.hasBody = false,
    this.removeHeaders = const [],
  });

  /// `overrides.headers`; a `null` value removes the key.
  final Map<String, dynamic>? headers;

  /// `overrides.queryParameters`; a `null` value removes the key.
  final Map<String, dynamic>? queryParameters;

  /// `overrides.body` (raw JSON, merged by key when a Map).
  final Object? body;

  /// Whether `overrides.body` was present.
  final bool hasBody;

  final List<String> removeHeaders;

  factory StacRetryInstruction.fromJson(Map<String, dynamic> json) {
    final overrides = json['overrides'];
    if (overrides != null && overrides is! Map) {
      throw const FormatException('retry.overrides must be an object');
    }
    final o = overrides == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(overrides as Map);
    Map<String, dynamic>? map(String name) {
      final v = o[name];
      if (v == null) return null;
      if (v is! Map) {
        throw FormatException('retry.overrides.$name must be an object');
      }
      return Map<String, dynamic>.from(v);
    }

    final remove = json['removeHeaders'];
    if (remove != null &&
        (remove is! List || remove.any((e) => e is! String))) {
      throw const FormatException(
        'retry.removeHeaders must be list of strings',
      );
    }
    return StacRetryInstruction(
      headers: map('headers'),
      queryParameters: map('queryParameters'),
      body: o['body'],
      hasBody: o.containsKey('body'),
      removeHeaders: remove == null
          ? const []
          : List<String>.from(remove as List),
    );
  }
}
