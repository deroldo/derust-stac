import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/framework/stac.dart';
import 'package:stac/src/recovery/stac_recovery_run.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_logger/stac_logger.dart';

/// Actions that open something and finish only when it is closed.
final Set<String> _navigationActions = {
  ActionType.navigate.name,
  ActionType.showDialog.name,
  ActionType.showModalBottomSheet.name,
};

/// Runs one action or a list of actions in sequence, awaiting each (except
/// navigation actions, which are fired and not awaited). Returns `false` as
/// soon as the request is no longer [alive] (the rest is dropped).
///
/// Callbacks are not the request of a recovery's `recover` themselves.
Future<bool> stacRunRequestActions(
  BuildContext context,
  Object? actions,
  bool Function() alive,
) => stacRunNested(() => _runActionList(context, actions, alive));

Future<bool> _runActionList(
  BuildContext context,
  Object? actions,
  bool Function() alive,
) async {
  if (!alive()) return false;
  if (actions == null) return true;
  final list = actions is List ? actions : [actions];
  for (final action in list) {
    if (action is! Map) {
      Log.e(
        StacGlobalState.instance.redact(
          'networkRequest callback expects actions, got $action',
        ),
      );
      continue;
    }
    final json = Map<String, dynamic>.from(action);
    if (_navigationActions.contains(json['actionType'])) {
      // Opening a screen/dialog completes only when it is closed (and
      // `pushReplacement` never completes for the origin): waiting would
      // hold back `onFinally`. The navigate action runs its own
      // `onResult`/`onCancel` when the destination returns.
      final pending = Stac.onCallFromJson(json, context);
      if (pending is Future) {
        unawaited(
          pending.then<void>(
            (_) {},
            onError: (Object e) => Log.e(
              StacGlobalState.instance.redact('navigation action failed: $e'),
            ),
          ),
        );
      }
    } else {
      await Stac.onCallFromJson(json, context);
    }
    if (!alive()) return false;
  }
  return true;
}

/// `response` as seen by bindings: `{body, statusCode, headers}`.
Map<String, Object?> stacResponseVars(Response<dynamic>? response) {
  Object? body = response?.data;
  if (body is String) {
    try {
      body = jsonDecode(body);
    } catch (_) {
      // Not JSON: keep the text.
    }
  }
  return {
    'body': body,
    'statusCode': response?.statusCode,
    'headers': {
      for (final e
          in response?.headers.map.entries ??
              const <MapEntry<String, List<String>>>[])
        e.key: e.value,
    },
  };
}
