import 'package:stac/src/recovery/stac_recovery_instruction.dart';

/// Server error envelope, version 1
/// (`Content-Type: application/vnd.stac.error+json`).
///
/// `screen` and `action` are kept as raw JSON for the runtime to parse later.
class StacErrorEnvelope {
  const StacErrorEnvelope({
    required this.version,
    this.code,
    this.message,
    this.screen,
    this.action,
    this.recovery,
  });

  static const int supportedVersion = 1;

  final int version;
  final String? code;
  final String? message;

  /// Raw Stac widget JSON.
  final Map<String, dynamic>? screen;

  /// Raw Stac action JSON.
  final Map<String, dynamic>? action;

  final StacRecoveryInstruction? recovery;

  /// Parses [json]; throws [FormatException] when malformed.
  factory StacErrorEnvelope.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('envelope.version must be an int');
    }
    final code = json['code'];
    final message = json['message'];
    if (code != null && code is! String) {
      throw const FormatException('envelope.code must be a string');
    }
    if (message != null && message is! String) {
      throw const FormatException('envelope.message must be a string');
    }
    Map<String, dynamic>? obj(String name) {
      final v = json[name];
      if (v == null) return null;
      if (v is! Map) throw FormatException('envelope.$name must be an object');
      return Map<String, dynamic>.from(v);
    }

    final recovery = obj('recovery');
    return StacErrorEnvelope(
      version: version,
      code: code as String?,
      message: message as String?,
      screen: obj('screen'),
      action: obj('action'),
      recovery: recovery == null
          ? null
          : StacRecoveryInstruction.fromJson(recovery),
    );
  }
}
