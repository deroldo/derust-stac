import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/stac.dart';
import 'package:stac_logger/stac_logger.dart';

class StacSwitchParser extends StacParser<StacSwitch> {
  const StacSwitchParser();

  @override
  String get type => "switch";

  @override
  StacSwitch getModel(Map<String, dynamic> json) => StacSwitch.fromJson(json);

  @override
  Widget parse(BuildContext context, StacSwitch model) {
    return _SwitchWidget(model: model);
  }
}

class _SwitchWidget extends StatefulWidget {
  const _SwitchWidget({required this.model});

  final StacSwitch model;

  @override
  State<_SwitchWidget> createState() => _SwitchWidgetState();
}

class _SwitchWidgetState extends State<_SwitchWidget> {
  bool isSelected = false;

  @override
  void initState() {
    super.initState();
    isSelected = widget.model.value ?? false;
  }

  @override
  void didUpdateWidget(covariant _SwitchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.value != widget.model.value) {
      isSelected = widget.model.value ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final StacSwitch model = widget.model;
    final StacSwitchType type = model.switchType ?? StacSwitchType.material;

    switch (type) {
      case StacSwitchType.cupertino:
        return _buildCupertinoSwitch(context, model);
      case StacSwitchType.adaptive:
        return _buildAdaptiveSwitch(context, model);
      case StacSwitchType.material:
        return _buildMaterialSwitch(context, model);
    }
  }

  /// Change the value of the switch as the user toggles it.
  void _onChanged(bool value) {
    isSelected = value;
    final onChanged = widget.model.onChanged;
    if (onChanged != null) {
      runWithStacActionVars({
        'event': {'value': value},
      }, () => Stac.onCallFromJson(onChanged.toJson(), context));
    }
    setState(() {});
  }

  Icon? thumbIconWidget(BuildContext context, Map<String, dynamic>? thumbIcon) {
    if (thumbIcon == null) return null;

    final Widget? widget = Stac.fromJson(thumbIcon, context);
    if (widget != null && widget is Icon) {
      return widget;
    }

    // A bound/hidden icon is wrapped by the state layer and cannot be handed
    // to the framework's WidgetStateProperty<Icon?>.
    if (widget != null) {
      Log.w(
        'switch thumbIcon must be a plain icon; bindings are not supported',
      );
    }
    return null;
  }

  Widget _buildCupertinoSwitch(BuildContext context, StacSwitch model) {
    return CupertinoSwitch(
      value: isSelected,
      onChanged: _onChanged,
      activeTrackColor: model.activeTrackColor?.toColor(context),
      inactiveTrackColor: model.inactiveTrackColor?.toColor(context),
      thumbColor: model.thumbColor?.toColor(context),
      applyTheme: model.applyTheme,
      focusColor: model.focusColor?.toColor(context),
      onLabelColor: model.onLabelColor?.toColor(context),
      offLabelColor: model.offLabelColor?.toColor(context),
      autofocus: model.autofocus ?? false,
      dragStartBehavior:
          model.dragStartBehavior?.parse ?? DragStartBehavior.start,
    );
  }

  Widget _buildAdaptiveSwitch(BuildContext context, StacSwitch model) {
    return Switch.adaptive(
      value: isSelected,
      onChanged: _onChanged,
      activeThumbColor: model.activeThumbColor?.toColor(context),
      activeTrackColor: model.activeTrackColor?.toColor(context),
      inactiveThumbColor: model.inactiveThumbColor?.toColor(context),
      inactiveTrackColor: model.inactiveTrackColor?.toColor(context),
      activeThumbImage: model.activeThumbImage != null
          ? NetworkImage(model.activeThumbImage!)
          : null,
      inactiveThumbImage: model.inactiveThumbImage != null
          ? NetworkImage(model.inactiveThumbImage!)
          : null,
      materialTapTargetSize: model.materialTapTargetSize?.parse,
      thumbColor: WidgetStateProperty.all(model.thumbColor?.toColor(context)),
      trackColor: WidgetStateProperty.all(model.trackColor?.toColor(context)),
      trackOutlineColor: WidgetStateProperty.all(
        model.trackOutlineColor?.toColor(context),
      ),
      trackOutlineWidth: WidgetStateProperty.all(model.trackOutlineWidth),
      thumbIcon: WidgetStateProperty.all(
        thumbIconWidget(context, model.thumbIcon?.toJson()),
      ),
      dragStartBehavior:
          model.dragStartBehavior?.parse ?? DragStartBehavior.start,
      focusColor: model.focusColor?.toColor(context),
      hoverColor: model.hoverColor?.toColor(context),
      overlayColor: WidgetStateProperty.all(
        model.overlayColor?.toColor(context),
      ),
      splashRadius: model.splashRadius ?? 0.0,
      autofocus: model.autofocus ?? false,
      applyCupertinoTheme: model.applyCupertinoTheme,
    );
  }

  Widget _buildMaterialSwitch(BuildContext context, StacSwitch model) {
    return Switch(
      value: isSelected,
      onChanged: _onChanged,
      activeThumbColor: model.activeThumbColor.toColor(context),
      activeTrackColor: model.activeTrackColor.toColor(context),
      inactiveThumbColor: model.inactiveThumbColor.toColor(context),
      inactiveTrackColor: model.inactiveTrackColor.toColor(context),
      activeThumbImage: model.activeThumbImage != null
          ? NetworkImage(model.activeThumbImage!)
          : null,
      inactiveThumbImage: model.inactiveThumbImage != null
          ? NetworkImage(model.inactiveThumbImage!)
          : null,
      thumbColor: WidgetStateProperty.all(model.thumbColor?.toColor(context)),
      trackColor: WidgetStateProperty.all(model.trackColor?.toColor(context)),
      trackOutlineColor: WidgetStateProperty.all(
        model.trackOutlineColor?.toColor(context),
      ),
      trackOutlineWidth: WidgetStateProperty.all(model.trackOutlineWidth),
      thumbIcon: WidgetStateProperty.all(
        thumbIconWidget(context, model.thumbIcon?.toJson()),
      ),
      materialTapTargetSize: model.materialTapTargetSize?.parse,
      dragStartBehavior:
          model.dragStartBehavior?.parse ?? DragStartBehavior.start,
      focusColor: model.focusColor?.toColor(context),
      hoverColor: model.hoverColor?.toColor(context),
      overlayColor: WidgetStateProperty.all(
        model.overlayColor?.toColor(context),
      ),
      splashRadius: model.splashRadius ?? 0.0,
      autofocus: model.autofocus ?? false,
    );
  }
}
