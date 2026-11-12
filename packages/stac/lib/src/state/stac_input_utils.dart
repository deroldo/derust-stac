import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/framework/stac.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_logger/stac_logger.dart';

/// Runs [action] exposing [value] as `event.value` (D9).
///
/// Fire and forget: input callbacks are synchronous, and the zone keeps
/// `event` visible to every action step, including async ones.
void callStacInputAction(
  StacAction? action,
  BuildContext context,
  Object? value,
) {
  if (action == null) return;
  unawaited(
    runWithStacActionVars({
      'event': {'value': value},
    }, () => Stac.onCallFromJson(action.toJson(), context)).catchError((
      Object e,
      StackTrace s,
    ) {
      Log.e('Input action failed: $e');
      return null;
    }),
  );
}

/// Text shown for a bound value of a text input: `null` is empty and scalars
/// are printed like the `+` operator does (D7). Other values are printed with
/// `toString`.
String stacInputText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Returns [json] with `initialValue` turned into text, so a bound number or
/// bool does not break model parsing. Returns [json] itself when nothing
/// changes.
Map<String, dynamic> coerceTextInitialValue(Map<String, dynamic> json) {
  final value = json['initialValue'];
  if (value == null || value is String) return json;
  return Map<String, dynamic>.of(json)..['initialValue'] = stacInputText(value);
}

/// Puts [text] in [controller] when it differs, moving the caret to the end.
/// Returns whether the controller changed.
bool syncTextController(TextEditingController controller, String text) {
  if (controller.text == text) return false;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  return true;
}
