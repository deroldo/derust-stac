import 'package:flutter/widgets.dart';
import 'package:stac/src/state/stac_binding.dart';
import 'package:stac/src/state/stac_scope.dart';

/// Rebuilds [build] whenever a state key cited by a binding in [json]
/// changes.
///
/// [json] is the own JSON of one widget. Bindings are re-resolved against the
/// current scope on every rebuild (children are not touched: they are
/// separate [StacReactive]s or plain widgets), and [build] re-runs the normal
/// parser with the context of this subtree, so theme-dependent values stay
/// current.
class StacReactive extends StatelessWidget {
  const StacReactive({
    required this.json,
    required Widget Function(
      BuildContext context,
      Map<String, dynamic> resolved,
    )
    build,
    super.key,
  }) : builder = build;

  final Map<String, dynamic> json;
  final Widget Function(BuildContext context, Map<String, dynamic> resolved)
  builder;

  @override
  Widget build(BuildContext context) {
    final scope = StacScope.of(context);
    final dependencies = StacBinding.dependenciesOf(json, isAction: false);
    if (dependencies.any(scope.isLocal)) {
      // Lexical variables (item, params, ...) change with the enclosing
      // StacLocalScope, so follow it.
      context.dependOnInheritedWidgetOfExactType<StacLocalScope>();
    }
    return ListenableBuilder(
      listenable: Listenable.merge(scope.listenablesFor(dependencies)),
      builder: (context, _) {
        final resolved =
            StacBinding.resolve(json, StacScope.of(context), isAction: false)
                as Map<String, dynamic>;
        return builder(context, resolved);
      },
    );
  }
}

/// A [StacReactive] standing where a [PreferredSizeWidget] is expected (the
/// `appBar` of a Scaffold, `bottom` of an AppBar): the casts of those
/// parsers keep working for a bound or hidden `appBar`/`tabBar`. The height
/// is computed by the caller from the values at build time. Other widgets
/// must not use it: for instance `TabBar` sizes itself from the tabs that are
/// [PreferredSizeWidget]s.
class StacPreferredSizeReactive extends StacReactive
    implements PreferredSizeWidget {
  const StacPreferredSizeReactive({
    required super.json,
    required super.build,
    required this.preferredSize,
    super.key,
  });

  @override
  final Size preferredSize;
}
