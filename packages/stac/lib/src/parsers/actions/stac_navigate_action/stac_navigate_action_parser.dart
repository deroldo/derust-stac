import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:stac/src/framework/framework.dart';
import 'package:stac/src/state/stac_action_vars.dart';
import 'package:stac/src/state/stac_pop_result.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

/// Key under which `params` travel in `arguments` for named routes (the app's
/// own route builder is responsible for reading it).
const String stacParamsArgumentKey = '__stacParams';

class StacNavigateActionParser extends StacActionParser<StacNavigateAction> {
  const StacNavigateActionParser();

  @override
  String get actionType => ActionType.navigate.name;

  @override
  StacNavigateAction getModel(Map<String, dynamic> json) =>
      StacNavigateAction.fromJson(json);

  @override
  FutureOr onCall(BuildContext context, StacNavigateAction model) {
    final params = model.params == null ? null : _deepCopy(model.params);
    final destination = _destination(context, model);
    final future = _navigate(
      context: context,
      navigationStyle: model.navigationStyle ?? NavigationStyle.push,
      routeName: model.routeName,
      result: model.hasResult ? StacPopResult(model.result) : null,
      arguments: _argumentsWith(model.arguments, params),
      builder: destination == null
          ? null
          : (routeContext) {
              final built = destination(routeContext);
              return params == null
                  ? built
                  : StacLocalScope(vars: {'params': params}, child: built);
            },
    );
    if (future == null) return null;
    return _awaitResult(context, model, future);
  }

  /// Builds the destination under the route's own context, so bindings and
  /// themes resolve there (and see `params`), not at the origin.
  static WidgetBuilder? _destination(
    BuildContext origin,
    StacNavigateAction model,
  ) {
    if (model.widgetJson != null) {
      return (context) =>
          Stac.fromJson(model.widgetJson, context) ?? const SizedBox();
    } else if (model.request != null) {
      // Created once (the request starts now), not on every route rebuild.
      final widget = Stac.fromNetwork(context: origin, request: model.request!);
      return (_) => widget;
    } else if (model.assetPath != null) {
      final widget = Stac.fromAssets(model.assetPath!);
      return (_) => widget;
    } else if (model.routeName != null &&
        (model.navigationStyle == null ||
            model.navigationStyle == NavigationStyle.push ||
            model.navigationStyle == NavigationStyle.pushReplacement ||
            model.navigationStyle == NavigationStyle.pushAndRemoveAll)) {
      // If a routeName is provided and we're using a push-style navigation,
      // render the remote screen using the Stac(routeName) widget.
      return (_) => Stac(routeName: model.routeName!);
    }
    return null;
  }

  static Map<String, dynamic>? _argumentsWith(
    Map<String, dynamic>? arguments,
    Object? params,
  ) {
    if (params == null) return arguments;
    return {...?arguments, stacParamsArgumentKey: params};
  }

  /// D10: only a [StacPopResult] runs `onResult`; a bare `null` is a
  /// cancellation. The returned future completes with the unwrapped value
  /// (what callers got before `StacPopResult` existed).
  static Future<dynamic> _awaitResult(
    BuildContext origin,
    StacNavigateAction model,
    Future<dynamic> pushed,
  ) async {
    final raw = await pushed;
    final value = StacPopResult.unwrap(raw);
    if (!origin.mounted) return value;
    final handler = raw is StacPopResult ? model.onResult : model.onCancel;
    if (handler == null) return value;
    if (raw is StacPopResult) {
      await runWithStacActionVars({'result': value}, () async {
        await Stac.onCallFromJson(handler, origin);
      });
    } else {
      await Stac.onCallFromJson(handler, origin);
    }
    return value;
  }

  static dynamic _deepCopy(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: _deepCopy(e.value)};
    }
    if (value is List) return [for (final v in value) _deepCopy(v)];
    return value;
  }

  static Future<dynamic>? _navigate({
    required BuildContext context,
    NavigationStyle navigationStyle = NavigationStyle.push,
    WidgetBuilder? builder,
    String? routeName,
    Object? result,
    Map<String, dynamic>? arguments,
  }) {
    // A route that carries a `routeName` is named, so Flutter reports it to the
    // browser (web URL) and `ModalRoute.of(context).settings.name` returns it.
    // Without a `routeName` the route stays unnamed, as before.
    Route<dynamic> route() => MaterialPageRoute(
      settings: routeName == null ? null : RouteSettings(name: routeName),
      builder: builder ?? (_) => const SizedBox(),
    );

    switch (navigationStyle) {
      case NavigationStyle.push:
        return Navigator.push(context, route());

      case NavigationStyle.pop:
        Navigator.pop(context, result);
        break;

      case NavigationStyle.pushReplacement:
        return Navigator.pushReplacement(context, route(), result: result);

      case NavigationStyle.pushAndRemoveAll:
        return Navigator.pushAndRemoveUntil(
          context,
          route(),
          // With a `routeName` every route below is removed, so the stack (and
          // the browser URL) is exactly the new screen. Without one the
          // established behavior is kept: the route named '/' stays.
          routeName == null ? ModalRoute.withName('/') : (_) => false,
        );

      case NavigationStyle.popAll:
        Navigator.popUntil(context, ModalRoute.withName('/'));
        break;

      case NavigationStyle.pushNamed:
        return Navigator.pushNamed(context, routeName!, arguments: arguments);

      case NavigationStyle.pushNamedAndRemoveAll:
        return Navigator.pushNamedAndRemoveUntil(
          context,
          routeName!,
          ModalRoute.withName('/'),
          arguments: arguments,
        );

      case NavigationStyle.pushReplacementNamed:
        return Navigator.pushReplacementNamed(
          context,
          routeName!,
          result: result,
          arguments: arguments,
        );
    }

    return null;
  }
}
