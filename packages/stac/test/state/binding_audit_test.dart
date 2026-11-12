import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Task 18 audit: for every widget type exemplified by the playground, one
/// scalar own property is replaced by `{"$state": "p"}` (with `p` equal to the
/// original value). The bound render must match the literal render, and after
/// changing `p` it must match the literal render of the new value, with no
/// logged error and no exception.
///
/// Explicit exceptions (type -> reason) live in [_baselineExceptions] and
/// [_propertyExceptions]. They are the list to document in reactivity.mdx.

const String _assetsDir = '../../stac_playground/assets/json';

/// Files that are not a single renderable widget tree.
const Set<String> _notWidgetFiles = {
  'example_dark_theme.json',
  'example_light_theme.json',
  'home_screen.json',
};

/// Widget types whose literal render already fails or is non-deterministic in
/// a plain widget test (before any binding), so they cannot be audited here.
const Map<String, String> _baselineExceptions = {
  'webView': 'needs a platform webview plugin; not renderable in flutter test',
};

/// Playground files whose widgets fetch over the network (Dio) and leave
/// pending timers in a plain widget test; the widgets in them cannot be
/// audited here (dynamicView, networkWidget and what they contain).
const Map<String, String> _fileExceptions = {
  'dynamic_list_view_example.json': 'dynamicView fetches over the network',
  'dynamic_view_example.json': 'dynamicView fetches over the network',
  'refresh_indicator_example.json': 'networkWidget fetches over the network',
};

/// `type.property` that cannot be audited by value substitution.
const Map<String, String> _propertyExceptions = {};

/// `type.property` whose value cannot be changed at runtime without breaking
/// an invariant of the underlying Flutter widget: only the initial (same
/// value) bound render is audited.
const Map<String, String> _noMutation = {
  'defaultTabController.length':
      'TabController length must match the number of tabs',
};

/// Replacement value for properties where "+1" would be out of range.
const Map<String, Object?> _mutationOverride = {
  'opacity.opacity': 0.5,
  'sliverOpacity.opacity': 0.5,
};

const Set<String> _wrapperTypes = {
  'StacReactive',
  'StacLocalScope',
  'StacStateScope',
  'StacScope',
  'KeyedSubtree',
  'ListenableBuilder',
};

typedef _Run = ({List<String> signature, List<String> logs, Object? exception});

Future<_Run> _render(
  WidgetTester t,
  Map<String, dynamic> json, {
  Map<String, Object?> state = const {},
  Future<void> Function(StacStateStore store)? then,
}) async {
  final logs = <String>[];
  Object? exception;
  // Network images cannot load in flutter test (HTTP 400); that failure is the
  // same with and without bindings, so it is not part of the audit.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains('HTTP request failed')) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
  await runZoned(
    () async {
      late StacStateStore store;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StacStateScope(
              key: UniqueKey(),
              initialState: state,
              child: Builder(
                builder: (c) {
                  store = StacStateScope.storeOf(c)!;
                  return StacService.fromJson(json, c) ??
                      const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await t.pump();
      if (then != null) {
        await then(store);
        await t.pump();
      }
      // Let implicit animations (e.g. card elevation) reach their end value.
      await t.pump(const Duration(seconds: 2));
      exception = t.takeException();
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );
  final signature = [
    for (final w in t.allWidgets)
      if (!_wrapperTypes.contains(w.runtimeType.toString())) _describe(w),
  ];
  return (signature: signature, logs: logs, exception: exception);
}

/// Type plus the widget's own diagnostic properties, with identity hashes
/// removed, so property changes (colors, sizes, text) are visible.
String _describe(Widget w) {
  final props = w
      .toDiagnosticsNode()
      .getProperties()
      .where((p) => p.name != 'key')
      .map((p) => '${p.name}=${p.toDescription()}')
      .join(',');
  return '${w.runtimeType}|$props'.replaceAll(RegExp(r'#[0-9a-f]{5}'), '#');
}

bool _isErrorLog(String line) => line.contains('ERROR') || line.contains('⛔');

typedef _Candidate = ({
  String type,
  List<Object> path,
  Object? value,
  String label,
});

bool _isChildMap(Map<dynamic, dynamic> m) {
  // Declaration time: the registry is not initialized yet, so any map with a
  // String type/actionType counts as a child.
  return m['actionType'] is String || m['type'] is String;
}

/// First scalar own property per distinct widget type in [root].
List<_Candidate> _candidates(Object? root, Set<String> seen) {
  final result = <_Candidate>[];

  _Candidate? scalarIn(Object? node, List<Object> path, String type) {
    if (node is Map) {
      // Prefer num/bool (changeable at runtime) over String (enums, colors).
      for (final wantString in [false, true]) {
        for (final e in node.entries) {
          if (e.key == 'type' || e.key == 'actionType') continue;
          final v = e.value;
          if (!(wantString ? v is String : (v is num || v is bool))) continue;
          return (
            type: type,
            path: [...path, e.key as String],
            value: v,
            label: '$type.${e.key}',
          );
        }
      }
      for (final e in node.entries) {
        final v = e.value;
        if (v is Map && !_isChildMap(v)) {
          final r = scalarIn(v, [...path, e.key as String], type);
          if (r != null) return r;
        }
      }
    }
    return null;
  }

  void walk(Object? node, List<Object> path) {
    if (node is Map) {
      final type = node['type'];
      if (type is String && seen.add(type)) {
        final c = scalarIn(node, path, type);
        if (c != null) result.add(c);
      }
      node.forEach((k, v) => walk(v, [...path, k as String]));
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        walk(node[i], [...path, i]);
      }
    }
  }

  walk(root, const []);
  return result;
}

dynamic _deepCopy(Object? o) => jsonDecode(jsonEncode(o));

dynamic _setAt(dynamic root, List<Object> path, Object? value) {
  final copy = _deepCopy(root);
  dynamic cur = copy;
  for (var i = 0; i < path.length - 1; i++) {
    cur = cur[path[i]];
  }
  cur[path.last] = value;
  return copy;
}

const Set<String> _freeTextKeys = {
  'data',
  'text',
  'label',
  'message',
  'title',
  'hintText',
};

Object? _changed(Object? v, String key) {
  if (v is bool) return !v;
  if (v is int) return v + 1;
  if (v is double) return v + 1;
  if (v is String && _freeTextKeys.contains(key)) return '$v!';
  return v; // other strings: not safely changeable (enums, colors, urls)
}

void main() {
  setUpAll(() => initStacForTest());

  final dir = Directory(_assetsDir);
  final seenTypes = <String>{};
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .where((f) => !_notWidgetFiles.contains(f.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('playground assets are reachable', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, dynamic>) continue;
    if (_fileExceptions.containsKey(name)) continue;
    for (final c in _candidates(json, seenTypes)) {
      final baseline = _baselineExceptions[c.type];
      if (baseline != null || _propertyExceptions.containsKey(c.label)) {
        continue;
      }
      testWidgets('$name: ${c.label} reacts to \$state', (t) async {
        t.view.physicalSize = const Size(1200, 2400);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);

        final next = _noMutation.containsKey(c.label)
            ? c.value
            : _mutationOverride.containsKey(c.label)
            ? _mutationOverride[c.label]
            : _changed(c.value, c.path.last as String);
        // Literal renders (reference).
        final literalBefore = await _render(t, json);
        final literalAfter = await _render(t, _setAt(json, c.path, next));
        if (literalBefore.exception != null ||
            literalBefore.logs.any(_isErrorLog)) {
          markTestSkipped(
            'baseline does not render in flutter test: '
            '${literalBefore.exception ?? literalBefore.logs.firstWhere(_isErrorLog)}',
          );
          return;
        }

        final bound = _setAt(json, c.path, {r'$state': 'audit_p'});
        final run = await _render(
          t,
          bound,
          state: {'audit_p': c.value},
          then: (store) async => store.write('audit_p', next),
        );
        expect(run.exception, isNull, reason: 'exception for ${c.label}');
        expect(
          run.logs.where(_isErrorLog),
          isEmpty,
          reason: 'error logged for ${c.label}',
        );
        expect(
          run.signature,
          literalAfter.signature,
          reason: 'bound render differs from literal render for ${c.label}',
        );
        // Same value stays equivalent to the original literal render.
        final same = await _render(t, bound, state: {'audit_p': c.value});
        expect(same.exception, isNull);
        expect(same.signature, literalBefore.signature);
      });
    }
  }
}
