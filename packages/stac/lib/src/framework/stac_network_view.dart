import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/recovery/stac_request_template.dart';
import 'package:stac/src/services/stac_network_service.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';

/// One request started by `Stac.fromNetwork`, with the life it owns: a
/// `CancelToken` cancelled when the view that shows it is disposed, and the
/// [StacRequestTemplate] that lets the request be sent again.
///
/// The request starts right away (when this is created), with the bindings
/// resolved at that moment against [context], exactly like before the view
/// existed.
class StacNetworkLoad {
  StacNetworkLoad._(this.token, this.future, this._disposed);

  /// Starts [request] (its JSON still holding the bindings).
  factory StacNetworkLoad.start(
    BuildContext context,
    StacNetworkRequest request,
  ) {
    final token = CancelToken();
    final disposed = _Flag();
    StacRequestTemplate? template;
    // An unmounted origin has no scope to capture; the request then repeats
    // from its RequestOptions.
    if (context.mounted) {
      template = StacRequestTemplate(
        json: request.toJson(),
        scope: StacCapturedScope.capture(context),
        alive: () => !disposed.value,
        requestKey: request.requestKey,
        cancelToken: token,
      );
    }
    final future = StacNetworkService.request(
      context,
      StacNetworkService.resolveBindings(context, request),
      cancelToken: token,
      template: template,
    );
    return StacNetworkLoad._(token, future, disposed);
  }

  final CancelToken token;
  final Future<Response?> future;
  final _Flag _disposed;

  /// Whether the view still wants the response: not disposed and the request
  /// not cancelled.
  bool alive() => !_disposed.value && !token.isCancelled;

  /// Called when the view goes away: cancels the request.
  void dispose() {
    _disposed.value = true;
    token.cancel('disposed');
  }
}

class _Flag {
  bool value = false;
}

/// The widget behind `Stac.fromNetwork`: shows [builder] over the response of
/// [load] and cancels the request when it leaves the tree.
class StacNetworkView extends StatefulWidget {
  const StacNetworkView({required this.load, required this.builder, super.key});

  final StacNetworkLoad load;
  final AsyncWidgetBuilder<Response?> builder;

  /// The enclosing view's [StacNetworkLoad.alive], or `null` outside one.
  static bool Function()? aliveOf(BuildContext context) => context
      .findAncestorStateOfType<_StacNetworkViewState>()
      ?.widget
      .load
      .alive;

  @override
  State<StacNetworkView> createState() => _StacNetworkViewState();
}

class _StacNetworkViewState extends State<StacNetworkView> {
  @override
  void didUpdateWidget(StacNetworkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load, widget.load)) oldWidget.load.dispose();
  }

  @override
  void dispose() {
    widget.load.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Response?>(
    future: widget.load.future,
    builder: widget.builder,
  );
}
