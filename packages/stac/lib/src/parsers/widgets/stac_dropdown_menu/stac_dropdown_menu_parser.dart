import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/parsers/foundation/geometry/stac_edge_insets_parser.dart';
import 'package:stac/src/parsers/foundation/geometry/stac_offset_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_align_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_input_type_parser.dart';
import 'package:stac/src/parsers/foundation/text/stac_text_style_parser.dart';
import 'package:stac/src/parsers/foundation/theme/stac_input_decoration_theme_parser.dart';
import 'package:stac/src/parsers/foundation/ui_components/stac_dropdown_menu_entry_parser.dart';
import 'package:stac/src/state/stac_input_utils.dart';
import 'package:stac/src/utils/input_formatters.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacDropdownMenuParser extends StacParser<StacDropdownMenu> {
  const StacDropdownMenuParser();

  @override
  String get type => WidgetType.dropdownMenu.name;

  @override
  StacDropdownMenu getModel(Map<String, dynamic> json) =>
      StacDropdownMenu.fromJson(json);

  @override
  Widget parse(BuildContext context, StacDropdownMenu model) {
    return _DropDownMenuWidget(model: model);
  }
}

class _DropDownMenuWidget extends StatefulWidget {
  const _DropDownMenuWidget({required this.model});

  final StacDropdownMenu model;

  @override
  State<_DropDownMenuWidget> createState() => _DropDownMenuWidgetState();
}

class _DropDownMenuWidgetState extends State<_DropDownMenuWidget> {
  final TextEditingController _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(_DropDownMenuWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // DropdownMenu only reacts to an `initialSelection` that matches an
    // entry; an external reset to null/unknown has to clear the text here.
    final selection = widget.model.initialSelection;
    if (oldWidget.model.initialSelection != selection) {
      final matches = widget.model.dropdownMenuEntries?.any(
        (entry) => entry.value == selection,
      );
      if (selection == null || matches != true) _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return DropdownMenu<dynamic>(
      initialSelection: model.initialSelection,
      focusNode: _focusNode,
      controller: _controller,
      dropdownMenuEntries:
          model.dropdownMenuEntries
              ?.map((e) => e.parse(context))
              .whereType<DropdownMenuEntry<dynamic>>()
              .toList() ??
          const <DropdownMenuEntry<dynamic>>[],
      enabled: model.enabled ?? true,
      onSelected: model.onSelected == null
          ? null
          : (value) => callStacInputAction(model.onSelected, context, value),
      width: model.width,
      menuHeight: model.menuHeight,
      leadingIcon: model.leadingIcon?.parse(context),
      trailingIcon: model.trailingIcon?.parse(context),
      label: model.label?.parse(context),
      hintText: model.hintText,
      helperText: model.helperText,
      errorText: model.errorText,
      selectedTrailingIcon: model.selectedTrailingIcon?.parse(context),
      enableFilter: model.enableFilter ?? true,
      enableSearch: model.enableSearch ?? true,
      keyboardType: model.keyboardType?.parse,
      textStyle: model.textStyle?.parse(context),
      textAlign: model.textAlign?.parse ?? TextAlign.start,
      inputDecorationTheme: model.inputDecorationTheme?.parse(context),
      requestFocusOnTap: model.requestFocusOnTap ?? false,
      expandedInsets: model.expandedInsets?.parse,
      alignmentOffset: model.alignmentOffset?.parse,
      inputFormatters: (model.inputFormatters ?? const <StacInputFormatter>[])
          .map<TextInputFormatter>((StacInputFormatter formatter) {
            switch (formatter.type) {
              case StacInputFormatterType.allow:
                return InputFormatterType.allow.format(formatter.rule ?? '');
              case StacInputFormatterType.deny:
                return InputFormatterType.deny.format(formatter.rule ?? '');
              case StacInputFormatterType.mask:
                return InputFormatterType.mask.format(
                  formatter.rule ?? '',
                  mask: formatter.mask,
                );
            }
          })
          .toList(),
    );
  }
}
