import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

extension StacWidgetParser on StacWidget? {
  Widget? parse(BuildContext context) {
    if (this == null) {
      return null;
    }

    return Stac.fromJson(this!.toJson(), context);
  }

  PreferredSizeWidget? parsePreferredSizeWidget(BuildContext context) {
    if (this == null) {
      return null;
    }

    final Widget? widget = Stac.fromJson(this!.toJson(), context);

    if (widget == null || widget is PreferredSizeWidget) {
      return widget as PreferredSizeWidget?;
    }
    // Error widgets and other stand-ins still have to fit the slot.
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: widget,
    );
  }
}

extension StacWidgetListParser on List<StacWidget>? {
  List<Widget>? parseList(BuildContext context) {
    if (this == null) {
      return null;
    }

    return this!
        .map((e) => e.parse(context) ?? const SizedBox.shrink())
        .toList();
  }
}
