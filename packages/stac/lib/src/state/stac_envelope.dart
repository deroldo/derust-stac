import 'dart:convert';

import 'package:stac/src/state/stac_binding.dart';
import 'package:stac_logger/stac_logger.dart';

/// Strategy that makes a widget without a native `enabled` inert (or active
/// again) by editing its JSON. Filled by Task 10.
typedef StacDisableStrategy =
    Map<String, dynamic> Function(Map<String, dynamic> json, bool enabled);

/// Value property and change event that `bind` maps to, per widget type.
typedef StacBindTarget = ({String valueProp, String eventProp});

/// Cross-cutting properties every widget accepts: `visible`, `enabled` and
/// `bind`.
class StacEnvelope {
  const StacEnvelope._();

  /// D9 table. `radio` is not here on purpose: `bind` belongs on the
  /// `radioGroup` (Task 8 reports a bound `radio` as an error).
  static const Map<String, StacBindTarget> bindTarget = {
    'checkBox': (valueProp: 'value', eventProp: 'onChanged'),
    'switch': (valueProp: 'value', eventProp: 'onChanged'),
    'slider': (valueProp: 'value', eventProp: 'onChanged'),
    'radioGroup': (valueProp: 'groupValue', eventProp: 'onChanged'),
    'textField': (valueProp: 'initialValue', eventProp: 'onChanged'),
    'textFormField': (valueProp: 'initialValue', eventProp: 'onChanged'),
    'dropdownMenu': (valueProp: 'initialSelection', eventProp: 'onSelected'),
  };

  /// Extension point (Task 10): how `enabled` is applied to widgets that have
  /// no native `enabled`. Types absent here receive `enabled` untouched.
  static final Map<String, StacDisableStrategy> disableStrategy = {};

  /// `visible` is a native property of these; the others are hidden by the
  /// envelope.
  static const Set<String> _nativeVisible = {'visibility', 'sliverVisibility'};

  static bool hasEnvelopeKeys(Map<String, dynamic> json) =>
      json.containsKey('bind') ||
      json.containsKey('visible') ||
      json.containsKey('enabled');

  /// D9: rewrites `bind: "k"` into `<valueProp>: {"$state": "k"}` and
  /// `<eventProp>: multiAction(sync)[setState {k: event.value}, original]`,
  /// so the store is written before the original callback runs. Returns
  /// [json] itself when there is no `bind`.
  static Map<String, dynamic> rewriteBind(
    Map<String, dynamic> json,
    String type,
  ) {
    if (!json.containsKey('bind')) return json;
    final result = Map<String, dynamic>.of(json);
    final key = result.remove('bind');
    final target = bindTarget[type];
    if (target == null) {
      Log.w('"bind" is not supported by widget "$type"; ignored');
      return result;
    }
    if (key is! String || key.trim().isEmpty) {
      Log.e('"bind" of "$type" must be a state key name, got $key; ignored');
      return result;
    }
    result[target.valueProp] = {r'$state': key};
    final write = <String, dynamic>{
      'actionType': 'setState',
      'values': {
        key: {r'$state': 'event.value'},
      },
    };
    final original = result[target.eventProp];
    result[target.eventProp] = original == null
        ? write
        : {
            'actionType': 'multiAction',
            'sync': true,
            'actions': [write, if (original is List) ...original else original],
          };
    return result;
  }

  /// Applies `visible` and `enabled` to an already resolved [json].
  ///
  /// Returns `null` when the widget must not be shown. Invalid or `null`
  /// results count as `false` (D6).
  static Map<String, dynamic>? apply(Map<String, dynamic> json, String type) {
    if (!json.containsKey('visible') && !json.containsKey('enabled')) {
      return json;
    }
    var result = json;
    if (result.containsKey('visible')) {
      final visible = StacBinding.strictBool(result['visible'], 'visible');
      if (_nativeVisible.contains(type)) {
        result = Map<String, dynamic>.of(result)..['visible'] = visible;
      } else {
        if (!visible) return null;
        result = Map<String, dynamic>.of(result)..remove('visible');
      }
    }
    if (result.containsKey('enabled')) {
      final enabled = StacBinding.strictBool(result['enabled'], 'enabled');
      result = Map<String, dynamic>.of(result)..['enabled'] = enabled;
      final strategy = disableStrategy[type];
      if (strategy != null) result = strategy(result, enabled);
    }
    return result;
  }

  /// Text widgets accept any bound value: `null` becomes an empty text and
  /// scalars are printed like the `+` operator does (D6, D7). Only used for
  /// JSON that went through binding resolution.
  static Map<String, dynamic> coerceResolved(
    Map<String, dynamic> json,
    String type,
  ) {
    if ((type != 'text' && type != 'selectableText') ||
        !json.containsKey('data')) {
      return json;
    }
    final data = json['data'];
    if (data is String) return json;
    return Map<String, dynamic>.of(json)..['data'] = _asText(data);
  }

  static String _asText(Object? value) {
    if (value == null) return '';
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    if (value is num || value is bool) return value.toString();
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
