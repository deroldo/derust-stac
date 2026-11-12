import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

class StacInkwellParser extends StacParser<StacInkWell> {
  const StacInkwellParser();

  @override
  String get type => WidgetType.inkWell.name;

  @override
  StacInkWell getModel(Map<String, dynamic> json) {
    return StacInkWell.fromJson(json);
  }

  @override
  Widget parse(BuildContext context, StacInkWell model) {
    return InkWell(
      onTap: model.onTap == null ? null : () => model.onTap!.parse(context),
      onDoubleTap: model.onDoubleTap == null
          ? null
          : () => model.onDoubleTap!.parse(context),
      onLongPress: model.onLongPress == null
          ? null
          : () => model.onLongPress!.parse(context),
      onTapCancel: model.onTapCancel == null
          ? null
          : () => model.onTapCancel!.parse(context),
      onSecondaryTap: model.onSecondaryTap == null
          ? null
          : () => model.onSecondaryTap!.parse(context),
      onSecondaryTapCancel: model.onSecondaryTapCancel == null
          ? null
          : () => model.onSecondaryTapCancel!.parse(context),
      onTapDown: model.onTapDown == null
          ? null
          : (_) => model.onTapDown!.parse(context),
      onTapUp: model.onTapUp == null
          ? null
          : (_) => model.onTapUp!.parse(context),
      onSecondaryTapUp: model.onSecondaryTapUp == null
          ? null
          : (_) => model.onSecondaryTapUp!.parse(context),
      onSecondaryTapDown: model.onSecondaryTapDown == null
          ? null
          : (_) => model.onSecondaryTapDown!.parse(context),
      onHighlightChanged: model.onHighlightChanged == null
          ? null
          : (_) => model.onHighlightChanged!.parse(context),
      onHover: model.onHover == null
          ? null
          : (_) => model.onHover!.parse(context),
      onFocusChange: model.onFocusChange == null
          ? null
          : (_) => model.onFocusChange!.parse(context),
      mouseCursor: model.mouseCursor?.parse,
      focusColor: model.focusColor?.toColor(context),
      hoverColor: model.hoverColor?.toColor(context),
      highlightColor: model.highlightColor?.toColor(context),
      overlayColor: model.overlayColor == null
          ? null
          : WidgetStateProperty.all(model.overlayColor!.toColor(context)),
      splashColor: model.splashColor?.toColor(context),
      radius: model.radius,
      borderRadius: model.borderRadius?.parse,
      customBorder: model.customBorder?.parse(context),
      enableFeedback: model.enableFeedback ?? true,
      excludeFromSemantics: model.excludeFromSemantics ?? false,
      canRequestFocus: model.canRequestFocus ?? true,
      autofocus: model.autofocus ?? false,
      hoverDuration: model.hoverDuration?.parse,
      child: model.child.parse(context),
    );
  }
}
