import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Documentation pages whose ```json blocks are checked, relative to the
/// repository root. Later tasks append the pages they add here.
const List<String> docsExamplePages = [
  'docs/concepts/state.mdx',
  'docs/concepts/bindings_and_expressions.mdx',
  'docs/concepts/reactivity.mdx',
  'docs/actions/set_state.mdx',
  'docs/actions/increment_state.mdx',
  'docs/actions/decrement_state.mdx',
  'docs/actions/toggle_state.mdx',
  'docs/actions/reset_state.mdx',
  'docs/actions/append_state.mdx',
  'docs/widgets/text.mdx',
  'docs/widgets/conditional.mdx',
];

/// Pages checked only for valid JSON (their blocks are older examples that are
/// not guaranteed to render without a full app around them).
const List<String> docsJsonOnlyPages = <String>[];

/// 1-based block numbers that are rendered by hand elsewhere or that predate
/// state and log unrelated problems (per page).
const Map<String, Set<int>> docsRenderSkips = {
  // Pre-existing example using an icon name that does not exist.
  'docs/widgets/conditional.mdx': {3},
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

void main() {
  setUpAll(() async {
    await initStacForTest();
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
            final logs = await _captureLogs(() async {
              await pumpStac(tester, json);
              await tester.pump();
              // Exercise the actions: tap every enabled button once.
              for (final type in const [
                ElevatedButton,
                FilledButton,
                OutlinedButton,
                TextButton,
              ]) {
                final buttons = find.byType(type);
                for (var i = 0; i < buttons.evaluate().length; i++) {
                  await tester.tap(buttons.at(i), warnIfMissed: false);
                  await tester.pump();
                }
              }
            });
            final problems = logs.where(_problemLog.hasMatch).toList();
            expect(
              problems,
              isEmpty,
              reason: '${example.name} logged:\n${logs.join('\n')}',
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    });
  }
}
