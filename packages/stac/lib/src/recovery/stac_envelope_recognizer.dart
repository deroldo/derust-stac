import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:stac/src/recovery/stac_error_envelope.dart';
import 'package:stac_logger/stac_logger.dart';

/// Recognizes a server error envelope in a response. Pure and total: never
/// throws, and only looks at "2xx or not", the content type and the body.
class StacEnvelopeRecognizer {
  const StacEnvelopeRecognizer._();

  static const String contentType = 'application/vnd.stac.error+json';

  /// Returns the envelope, or `null` when [response] is not one (a regular
  /// error). Unsupported or malformed envelopes return `null` and are logged.
  static StacErrorEnvelope? recognize(Response<dynamic> response) {
    try {
      final status = response.statusCode;
      if (status == null || (status >= 200 && status < 300)) return null;

      final header = response.headers.value(Headers.contentTypeHeader);
      if (header == null) return null;
      final mime = header.split(';').first.trim().toLowerCase();
      if (mime != contentType) return null;

      var body = response.data;
      if (body is String) {
        try {
          body = jsonDecode(body);
        } catch (_) {
          Log.w('stac recovery: error envelope body is not valid JSON');
          return null;
        }
      }
      if (body is! Map) {
        Log.w('stac recovery: error envelope body is not a JSON object');
        return null;
      }
      final json = Map<String, dynamic>.from(body);
      final version = json['version'];
      if (version is! int) {
        Log.w('stac recovery: error envelope version is not an integer');
        return null;
      }
      if (version != StacErrorEnvelope.supportedVersion) {
        Log.w('stac recovery: unsupported error envelope version $version');
        return null;
      }
      return StacErrorEnvelope.fromJson(json);
    } catch (e) {
      // Do not print the body: it may carry state values.
      Log.w(
        'stac recovery: malformed error envelope ignored (${e.runtimeType}: ${_msg(e)})',
      );
      return null;
    }
  }

  static String _msg(Object e) => e is FormatException ? e.message : '';
}
