import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Documentation pages whose ```json blocks are checked, relative to the
/// repository root. Later tasks append the pages they add here.
const List<String> docsExamplePages = [
  'docs/concepts/state.mdx',
  'docs/concepts/bindings_and_expressions.mdx',
  'docs/concepts/reactivity.mdx',
  'docs/concepts/state_reference.mdx',
  'docs/actions/set_state.mdx',
  'docs/actions/increment_state.mdx',
  'docs/actions/decrement_state.mdx',
  'docs/actions/toggle_state.mdx',
  'docs/actions/reset_state.mdx',
  'docs/actions/append_state.mdx',
  'docs/widgets/text.mdx',
  'docs/widgets/conditional.mdx',
  // Phase 2: inputs.
  'docs/widgets/check_box.mdx',
  'docs/widgets/switch.mdx',
  'docs/widgets/slider.mdx',
  'docs/widgets/radio_group.mdx',
  'docs/widgets/text_field.mdx',
  'docs/widgets/text_form_field.mdx',
  'docs/widgets/dropdown_menu.mdx',
  'docs/widgets/elevated_button.mdx',
  'docs/widgets/filled_button.mdx',
  'docs/widgets/outlined_button.mdx',
  'docs/widgets/text_button.mdx',
  'docs/widgets/icon_button.mdx',
  'docs/guides/state_recipes.mdx',
  // Phase 3: requests and navigation.
  'docs/actions/network_request.mdx',
  'docs/actions/cancel_request.mdx',
  'docs/actions/navigate.mdx',
  // Phase 4: lists and collection actions.
  'docs/actions/remove_from_state.mdx',
  'docs/actions/toggle_item.mdx',
  'docs/widgets/listview.mdx',
  'docs/widgets/grid_view.mdx',
  'docs/widgets/page_view.mdx',
  'docs/widgets/sliver_list.mdx',
  'docs/widgets/sliver_grid.mdx',
];

/// Pages checked only for valid JSON (their blocks are older examples that are
/// not guaranteed to render without a full app around them).
const List<String> docsJsonOnlyPages = <String>[];

/// 1-based block numbers that are rendered by hand elsewhere or that predate
/// state and log unrelated problems (per page).
const Map<String, Set<int>> docsRenderSkips = {
  // Pre-existing example using an icon name that does not exist.
  'docs/widgets/conditional.mdx': {3},
  // Older examples of pages that gained a state section: they predate the
  // state work and need a full app around them (form, theme, scrolling).
  'docs/widgets/check_box.mdx': {1},
  'docs/widgets/radio_group.mdx': {1},
  'docs/widgets/text_form_field.mdx': {2, 3},
  'docs/widgets/elevated_button.mdx': {1},
  'docs/widgets/filled_button.mdx': {1},
  'docs/widgets/outlined_button.mdx': {1},
  'docs/widgets/text_button.mdx': {1},
  'docs/widgets/grid_view.mdx': {1},
};

/// Output of the logger that signals a problem (error or warning).
final RegExp _problemLog = RegExp(r'ERROR|WARNING|⛔|⚠|Exception');

/// One ```json block of a page.
class DocExample {
  DocExample(this.page, this.index, this.source);

  final String page;
  final int index;
  final String source;

  String get name => '$page #$index';

  dynamic decode() => jsonDecode(source);
}

File _repoFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final file = File('${dir.path}/$relative');
    if (file.existsSync()) return file;
    dir = dir.parent;
  }
  throw StateError('Cannot find $relative from ${Directory.current.path}');
}

/// Extracts the ```json blocks (also ```json JSON inside a CodeGroup).
List<DocExample> extractJsonExamples(String page) {
  final text = _repoFile(page).readAsStringSync();
  final pattern = RegExp(r'```json[^\n]*\n(.*?)\n\s*```', dotAll: true);
  var index = 0;
  return [
    for (final m in pattern.allMatches(text))
      DocExample(page, ++index, m.group(1)!),
  ];
}

Future<List<String>> _captureLogs(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// Answers every request with the same small JSON document, so documentation
/// examples that call a backend can run without a network.
class _DocsAdapter implements HttpClientAdapter {
  static const Map<String, Object?> body = {
    'items': [
      {'id': 1, 'name': 'Ana'},
    ],
    'name': 'Ana',
    'city': 'Rio',
    'token': 'abc',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async {
    await initStacForTest(dio: Dio()..httpClientAdapter = _DocsAdapter());
  });
  setUp(() => StacGlobalState.instance.clear());

  for (final page in [...docsExamplePages, ...docsJsonOnlyPages]) {
    final renders = docsExamplePages.contains(page);
    group(page, () {
      final examples = extractJsonExamples(page);

      test('has JSON examples', () {
        expect(examples, isNotEmpty);
      });

      for (final example in examples) {
        test('${example.name} is valid JSON', () {
          expect(example.decode, returnsNormally);
        });

        if (!renders) continue;
        final json = example.decode();
        if (json is! Map<String, dynamic>) continue;

        if (json.containsKey('type') &&
            !(docsRenderSkips[page]?.contains(example.index) ?? false)) {
          testWidgets('${example.name} renders without logged problems', (
            tester,
          ) async {
            final errors = <String>[];
            final previousOnError = FlutterError.onError;
            FlutterError.onError = (details) =>
                errors.add(details.exceptionAsString());
            final logs = await _captureLogs(() async {
              await pumpStac(tester, json);
              await tester.pump();
              // Exercise the actions: tap every enabled button, twice, so
              // flows that open a second screen get their buttons tapped too.
              for (var round = 0; round < 2; round++) {
                for (final type in const [
                  ElevatedButton,
                  FilledButton,
                  OutlinedButton,
                  TextButton,
                ]) {
                  final buttons = find.byType(type);
                  for (var i = 0; i < buttons.evaluate().length; i++) {
                    await tester.tap(buttons.at(i), warnIfMissed: false);
                    await tester.pump(const Duration(milliseconds: 100));
                  }
                }
              }
            });
            FlutterError.onError = previousOnError;
            final problems = logs.where(_problemLog.hasMatch).toList();
            expect(
              problems,
              isEmpty,
              reason: '${example.name} logged:\n${logs.join('\n')}',
            );
            expect(errors, isEmpty, reason: '${example.name} threw');
          });
        }
      }
    });
  }
}
