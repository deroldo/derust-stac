import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/parsers/core/stac_action_parser.dart';
import 'package:stac/src/parsers/foundation/decoration/stac_input_decoration_parser.dart';
import 'package:stac/src/parsers/foundation/forms/stac_input_formatter_type_parser.dart';
import 'package:stac/src/parsers/foundation/geometry/stac_edge_insets_parser.dart';
import 'package:stac/src/parsers/foundation/interaction/stac_drag_start_behavior_parser.dart';
import 'package:stac/src/parsers/foundation/interaction/stac_mouse_cursor_parser.dart';
import 'package:stac/src/parsers/foundation/interaction/stac_scroll_physics_parser.dart';
import 'package:stac/src/parsers/foundation/layout/stac_clip_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_align_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_capitalization_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_direction_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_input_action_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_input_type_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_style_parser.dart';
import 'package:stac/src/state/stac_input_utils.dart';
import 'package:stac/src/utils/color_utils.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacTextFieldParser extends StacParser<StacTextField> {
  const StacTextFieldParser({this.controller, this.focusNode});

  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  StacTextField getModel(Map<String, dynamic> json) =>
      StacTextField.fromJson(coerceTextInitialValue(json));

  @override
  String get type => WidgetType.textField.name;

  @override
  Widget parse(BuildContext context, StacTextField model) {
    return _StacTextField(
      model: model,
      controller: controller,
      focusNode: focusNode,
    );
  }
}

/// Owns the [TextEditingController] so that rebuilds (for example when the
/// bound state key changes) keep the focus, the caret and the typed text.
class _StacTextField extends StatefulWidget {
  const _StacTextField({required this.model, this.controller, this.focusNode});

  final StacTextField model;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<_StacTextField> createState() => _StacTextFieldState();
}

class _StacTextFieldState extends State<_StacTextField> {
  TextEditingController? _ownController;

  TextEditingController get _controller => widget.controller ?? _ownController!;

  @override
  void initState() {
    super.initState();
    final initial = widget.model.initialValue ?? '';
    if (widget.controller == null) {
      _ownController = TextEditingController(text: initial);
    } else if (initial.isNotEmpty) {
      widget.controller!.text = initial;
    }
  }

  @override
  void didUpdateWidget(_StacTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ownController?.dispose();
      _ownController = widget.controller == null
          ? TextEditingController(text: widget.model.initialValue ?? '')
          : null;
    }
    // Only an incoming value change is written, and only when it differs from
    // what the field already shows: typing writes the store, the store comes
    // back here with the very same text and the caret must stay untouched.
    if (oldWidget.model.initialValue != widget.model.initialValue) {
      syncTextController(_controller, widget.model.initialValue ?? '');
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      keyboardType: model.keyboardType?.parse,
      textInputAction: model.textInputAction?.parse,
      textCapitalization:
          model.textCapitalization?.parse ?? TextCapitalization.none,
      textAlign: model.textAlign?.parse ?? TextAlign.start,
      textDirection: model.textDirection?.parse,
      readOnly: model.readOnly ?? false,
      showCursor: model.showCursor,
      autofocus: model.autofocus ?? false,
      obscuringCharacter: model.obscuringCharacter ?? '•',
      maxLines: model.maxLines,
      minLines: model.minLines,
      maxLength: model.maxLength,
      obscureText: model.obscureText ?? false,
      enableSuggestions: model.enableSuggestions ?? true,
      enabled: model.enabled,
      expands: model.expands ?? false,
      cursorWidth: model.cursorWidth ?? 2.0,
      cursorHeight: model.cursorHeight,
      cursorColor: model.cursorColor?.toColor(context),
      style: model.style?.parse(context),
      decoration: model.decoration?.parse(context),
      scrollPadding: model.scrollPadding?.parse ?? const EdgeInsets.all(20.0),
      enableInteractiveSelection: model.enableInteractiveSelection,
      mouseCursor: model.mouseCursor?.parse,
      dragStartBehavior:
          model.dragStartBehavior?.parse ?? DragStartBehavior.start,
      scrollPhysics: model.scrollPhysics?.parse,
      restorationId: model.restorationId,
      clipBehavior: model.clipBehavior?.parse ?? Clip.hardEdge,
      autofillHints: model.autofillHints,
      inputFormatters: model.inputFormatters
          ?.map(
            (formatter) => formatter.type.parse.format(
              formatter.rule ?? '',
              mask: formatter.mask,
            ),
          )
          .toList(),
      onTap: model.onTap == null ? null : () => model.onTap!.parse(context),
      onChanged: model.onChanged == null
          ? null
          : (value) => callStacInputAction(model.onChanged, context, value),
      onEditingComplete: model.onEditingComplete == null
          ? null
          : () => model.onEditingComplete!.parse(context),
      onSubmitted: model.onSubmitted == null
          ? null
          : (value) => model.onSubmitted!.parse(context),
    );
  }
}
