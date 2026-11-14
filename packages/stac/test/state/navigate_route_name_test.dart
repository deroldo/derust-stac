import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// `navigate.routeName` names the pushed route (RouteSettings), so Flutter
/// reports it to the browser URL and `ModalRoute.settings.name` returns it,
/// also for `push`, `pushReplacement` and `pushAndRemoveAll` with a `request`.
/// The request itself is still fetched from its own URL.

/// Tracks the live route stack (names included).
class _Stack extends NavigatorObserver {
  final List<Route<dynamic>> routes = [];

  List<String?> get names => [for (final r in routes) r.settings.name];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = routes.indexOf(oldRoute!);
    if (i >= 0) routes[i] = newRoute!;
  }
}

void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  late _Stack stack;
  late List<String> reportedUris;

  setUp(() {
    adapter.requests.clear();
    stack = _Stack();
    reportedUris = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          if (call.method == 'routeInformationUpdated') {
            final args = call.arguments as Map;
            reportedUris.add('${args['uri'] ?? args['location']}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null);
  });

  Map<String, dynamic> go(
    Map<String, dynamic> navigate, [
    String label = 'go',
  ]) => {
    'type': 'textButton',
    'onPressed': {'actionType': 'navigate', ...navigate},
    'child': {'type': 'text', 'data': label},
  };

  Map<String, dynamic> request(String path) => {
    'actionType': 'networkRequest',
    'url': 'https://api.test$path',
    'method': 'get',
  };

  Future<void> pumpApp(
    WidgetTester tester,
    Map<String, dynamic> home, {
    RouteFactory? onGenerateRoute,
  }) async {
    await initStacForTest(dio: dio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [stack],
        onGenerateRoute: onGenerateRoute,
        home: Scaffold(
          body: Builder(builder: (c) => StacService.fromJson(home, c)!),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  const screen = {'type': 'text', 'data': 'dest'};

  testWidgets('push with routeName names the route and reports the URL', (
    tester,
  ) async {
    adapter.enqueue(const FakeResponse(screen));
    await pumpApp(
      tester,
      go({
        'request': request('/v1/screens/profile'),
        'routeName': '/screens/profile?choose=true',
      }),
    );
    await tap(tester, 'go');

    expect(stack.names, ['/', '/screens/profile?choose=true']);
    expect(reportedUris.last, '/screens/profile?choose=true');
    // The screen is fetched from the request URL, not from the routeName.
    expect(
      adapter.requests.single.uri.toString(),
      'https://api.test/v1/screens/profile',
    );
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('without routeName the route stays unnamed (unchanged)', (
    tester,
  ) async {
    adapter.enqueue(const FakeResponse(screen));
    await pumpApp(tester, go({'request': request('/v1/screens/profile')}));
    final before = reportedUris.length;
    await tap(tester, 'go');

    expect(stack.names, ['/', null]);
    expect(reportedUris.length, before, reason: 'no URL update without a name');
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('pushReplacement with routeName renames the top route', (
    tester,
  ) async {
    adapter
      ..enqueue(
        FakeResponse(
          go({
            'navigationStyle': 'pushReplacement',
            'request': request('/v1/screens/b'),
            'routeName': '/screens/b',
          }, 'to b'),
        ),
      )
      ..enqueue(const FakeResponse(screen));
    await pumpApp(
      tester,
      go({'request': request('/v1/screens/a'), 'routeName': '/screens/a'}),
    );
    await tap(tester, 'go');
    expect(stack.names, ['/', '/screens/a']);

    await tap(tester, 'to b');
    expect(stack.names, ['/', '/screens/b']);
    expect(reportedUris.last, '/screens/b');
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('pushAndRemoveAll with routeName clears the stack', (
    tester,
  ) async {
    adapter
      ..enqueue(
        FakeResponse(
          go({
            'navigationStyle': 'pushAndRemoveAll',
            'request': request('/v1/screens/login'),
            'routeName': '/screens/login',
          }, 'logout'),
        ),
      )
      ..enqueue(const FakeResponse(screen));
    await pumpApp(
      tester,
      go({'request': request('/v1/screens/a'), 'routeName': '/screens/a'}),
    );
    await tap(tester, 'go');
    expect(stack.names, ['/', '/screens/a']);

    await tap(tester, 'logout');
    expect(stack.names, ['/screens/login'], reason: 'home and a are removed');
    expect(reportedUris.last, '/screens/login');
    expect(find.text('dest'), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    expect(nav.canPop(), isFalse);
  });

  testWidgets('pushAndRemoveAll without routeName keeps the "/" route', (
    tester,
  ) async {
    adapter
      ..enqueue(
        FakeResponse(
          go({
            'navigationStyle': 'pushAndRemoveAll',
            'request': request('/v1/screens/login'),
          }, 'logout'),
        ),
      )
      ..enqueue(const FakeResponse(screen));
    await pumpApp(tester, go({'request': request('/v1/screens/a')}));
    await tap(tester, 'go');
    await tap(tester, 'logout');

    expect(stack.names, ['/', null], reason: 'established behavior');
  });

  group('params with a named route (app builds the screen)', () {
    // What an app does for `navigationStyle: pushNamed`: Stac delivers the
    // params under `arguments['__stacParams']`; the app hands them to the
    // screen it builds with StacLocalScope.
    Route<dynamic>? onGenerateRoute(RouteSettings settings) {
      if (settings.name != '/welcome') return null;
      final args = settings.arguments;
      final params = args is Map ? args['__stacParams'] : null;
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => Scaffold(
          body: StacLocalScope(
            vars: {'params': ?params},
            child: Builder(
              builder: (c) => StacService.fromJson({
                'type': 'column',
                // A toast shown once on open, only when a message came along.
                'onInit': {
                  'actionType': 'showSnackBar',
                  'condition': {r'$expr': 'length(params.message) > 0'},
                  'content': {
                    'type': 'text',
                    'data': {r'$state': 'params.message'},
                  },
                },
                'children': [
                  {'type': 'text', 'data': 'welcome'},
                ],
              }, c)!,
            ),
          ),
        ),
      );
    }

    testWidgets('the screen reads params.* and shows the toast on open', (
      tester,
    ) async {
      await pumpApp(
        tester,
        go({
          'navigationStyle': 'pushNamed',
          'routeName': '/welcome',
          'params': {'message': 'Senha alterada. Entre com a nova senha.'},
        }),
        onGenerateRoute: onGenerateRoute,
      );
      await tap(tester, 'go');

      expect(find.text('welcome'), findsOneWidget);
      expect(
        find.text('Senha alterada. Entre com a nova senha.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(reportedUris.last, '/welcome');
    });

    testWidgets('after a reload (no params) no toast and no error', (
      tester,
    ) async {
      await pumpApp(
        tester,
        go({'navigationStyle': 'pushNamed', 'routeName': '/welcome'}),
        onGenerateRoute: onGenerateRoute,
      );
      await tap(tester, 'go');

      expect(find.text('welcome'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('showSnackBar content reads the screen state', (tester) async {
    await pumpApp(tester, {
      'type': 'column',
      'state': {'msg': 'salvo com sucesso'},
      'children': [
        {
          'type': 'textButton',
          'onPressed': {
            'actionType': 'showSnackBar',
            'content': {
              'type': 'text',
              'data': {r'$state': 'msg'},
            },
          },
          'child': {'type': 'text', 'data': 'toast'},
        },
      ],
    });
    await tap(tester, 'toast');
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('salvo com sucesso'),
      ),
      findsOneWidget,
    );
  });
}
