// Event list screen on Material 3 (intent 0002).
//
// Pumps LatestEventList (the body of ScheduledEventsPage) with the mock
// feed. ScheduledEventsPage itself is not pumped because its location
// permission check needs geolocator outside mock mode.

import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/event_header_card.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/responsive_card_grid.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/route_map_page.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_tiles.dart';
import 'support/fixtures.dart';
import 'support/grid.dart';

const startActions = {'RIDE', 'PRE-RIDE'};

Widget app(Widget home, {ThemeMode mode = ThemeMode.light}) {
  final dn = DayNight(mode: mode);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: dn),
      ChangeNotifierProvider(create: (_) => ControlState()),
      ChangeNotifierProvider(create: (_) => SourceSelection()),
    ],
    child: MaterialApp(
      scaffoldMessengerKey: AppSnack.messengerKey,
      theme: dn.dayTheme,
      darkTheme: dn.nightTheme,
      themeMode: mode,
      home: home,
    ),
  );
}

Widget eventList() => Scaffold(
      body: Builder(
        builder: (context) => Container(
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.all(16),
          child: const LatestEventList(eventFilter: EventFilter.all),
        ),
      ),
    );

/// Unmount so LatestEventList cancels its refresh timer.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

/// `.icon` / `.tonalIcon` constructors build private subclasses, so match
/// with `is` rather than `find.byType`.
Finder isA_<T>({bool skipOffstage = true}) =>
    find.byWidgetPredicate((w) => w is T, skipOffstage: skipOffstage);

/// Fill color the button actually renders with.
Color? fillOf(WidgetTester tester, Finder button) => tester
    .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first)
    .color;

String? labelOf(FilledButton b) {
  final child = b.child;
  return child is Text ? child.data : null;
}

void main() {
  late List<Event> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MySetting.initSharedPreferences();
    useMockServerForTests();
    // App code compares event times with DateTime.now(), so date the mock
    // feed relative to the real clock for RIDE / PRE-RIDE to be offered.
    MockServer.now = DateTime.now;
    events = await mockEvents();
    ScheduledEvents.events = events;
  });

  tearDown(() {
    ScheduledEvents.events = <Event>[];
    MockServer.now = DateTime.now;
  });

  // AC2 (intent 0002), superseded by AC6 (intent 0009): the event title is
  // now a titleLarge headline with a bolder weight.
  testWidgets('event title uses titleLarge, bold', (tester) async {
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    final theme = Theme.of(tester.element(find.byType(LatestEventList)));
    final role =
        theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700);
    final title =
        tester.widget<EventCard>(find.byType(EventCard).first).event.nameDist;
    final style = tester
        .renderObject<RenderParagraph>(find.text(title).first)
        .text
        .style!;
    expect(style.fontSize, role.fontSize);
    expect(style.fontWeight, role.fontWeight);
    expect(style.letterSpacing, role.letterSpacing);
    await unmount(tester);
  });

  // AC2 (intent 0002)
  testWidgets('header card uses titleLarge and bodyLarge', (tester) async {
    final event = events.first;
    await tester.pumpWidget(app(Scaffold(body: EventHeaderCard(event: event))));
    final theme = Theme.of(tester.element(find.byType(EventHeaderCard)));
    final name = tester
        .renderObject<RenderParagraph>(find.text(event.nameDist))
        .text
        .style!;
    expect(name.fontSize, theme.textTheme.titleLarge!.fontSize);
    expect(name.fontWeight, FontWeight.bold);
    final start = tester
        .renderObject<RenderParagraph>(find.textContaining('Start: '))
        .text
        .style!;
    expect(start.fontSize, theme.textTheme.bodyLarge!.fontSize);
  });

  // AC3 (intent 0002)
  testWidgets('event website icon uses colorScheme.primary', (tester) async {
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(AlertDialog)));
    final website = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.language_rounded));
    expect(website.color, theme.colorScheme.primary);

    // AC4 (intent 0002): dialog actions are secondary or tertiary.
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: isA_<FilledButton>()),
        findsNothing);
    expect(find.descendant(of: dialog, matching: isA_<ElevatedButton>()),
        findsNothing);
    expect(find.descendant(of: dialog, matching: isA_<OutlinedButton>()),
        findsNWidgets(2));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  // AC4 (intent 0002)
  testWidgets('each card has exactly one FilledButton, the start action',
      (tester) async {
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    final scheme =
        Theme.of(tester.element(find.byType(LatestEventList))).colorScheme;
    final cards = find.byType(EventCard, skipOffstage: false);
    expect(cards, findsWidgets);
    var checked = 0;
    for (final card in cards.evaluate()) {
      final filled = find.descendant(
          of: find.byWidget(card.widget),
          matching: isA_<FilledButton>(skipOffstage: false),
          skipOffstage: false);
      final buttons = tester.widgetList<FilledButton>(filled).toList();
      expect(buttons.length, lessThanOrEqualTo(1));
      if (buttons.isNotEmpty) {
        expect(startActions, contains(labelOf(buttons.single)));
        // Primary emphasis: filled with colorScheme.primary.
        expect(fillOf(tester, filled.first), scheme.primary);
        checked++;
      }
    }
    expect(checked, greaterThan(0),
        reason: 'mock feed should offer RIDE or PRE-RIDE');

    // "Update event data" is secondary (outlined), not filled.
    final update = find.ancestor(
        of: find.text('Update event data'), matching: isA_<OutlinedButton>());
    expect(update, findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Update event data'), matching: isA_<FilledButton>()),
        findsNothing);
    expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
    await unmount(tester);
  });

  // AC5 + AC6 (intent 0002)
  testWidgets('AppSnack shows an M3 SnackBar with the message', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox())));
    AppSnack.show('Hello rider');
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Hello rider'), findsOneWidget);
    // Info style takes its colors from the theme's snackBarTheme.
    expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, isNull);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  // AC5 + AC6 (intent 0002)
  testWidgets('RIDE without a rider ID shows the same error as a SnackBar',
      (tester) async {
    expect(AppSettings.isRusaIDSet, isFalse);
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    final ride = find.byWidgetPredicate(
        (w) => w is FilledButton && startActions.contains(labelOf(w)));
    // Cards are taller since the route sketch (intent 0009).
    await tester.ensureVisible(ride.first);
    await tester.pump();
    await tester.tap(ride.first);
    await tester.pump();
    expect(find.text("Can't RIDE. Rider ID not set."), findsOneWidget);
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    final scheme =
        Theme.of(tester.element(find.byType(LatestEventList))).colorScheme;
    expect(snack.backgroundColor, scheme.error);
    final text = tester
        .renderObject<RenderParagraph>(
            find.text("Can't RIDE. Rider ID not set."))
        .text
        .style!;
    expect(text.color, scheme.onError);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  // AC1 (intent 0010), superseding AC10 (intent 0009): flutter_map is the
  // one new dependency (latlong2 is its own coordinate type, at the range
  // flutter_map requires). No tile-cache package, SDK constraint unchanged.
  test('flutter_map dependency, no disk tile cache, same SDK constraint', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
        pubspec, contains(RegExp(r'^  flutter_map: \^8\.', multiLine: true)));
    expect(
        pubspec,
        contains(
            RegExp(r'^  latlong2: ">=0\.9\.1 <0\.11\.0"', multiLine: true)));
    expect(pubspec, contains("sdk: '>=2.18.6 <3.0.0'"));
    // Direct dependencies: the ones before this intent plus the map pair.
    // Anything else (e.g. a tile-cache package) fails here.
    final start = pubspec.indexOf('\ndependencies:') + 1;
    // Up to the next top-level key.
    final end =
        pubspec.indexOf(RegExp(r'^[a-z_]+:', multiLine: true), start + 1);
    final section = pubspec.substring(start, end);
    final names = RegExp(r'^  ([a-z0-9_]+):', multiLine: true)
        .allMatches(section)
        .map((m) => m.group(1))
        .toSet();
    expect(names, {
      'flutter',
      'shared_preferences',
      'http',
      'provider',
      'geolocator',
      'crypto',
      'flutter_launcher_icons',
      'path_provider',
      'url_launcher',
      'package_info_plus',
      'adaptive_theme',
      'screenshot',
      'share_plus',
      'upgrader',
      'win32',
      'confetti',
      'shimmer',
      'cupertino_icons',
      'flutter_map',
      'latlong2',
    });
  });

  group('responsive grid (intent 0012)', () {
    late List<FakeTileProvider> providers;

    setUp(() {
      providers = <FakeTileProvider>[];
      RouteMap.tileProviderFactory = () {
        final p = FakeTileProvider();
        providers.add(p);
        return p;
      };
    });

    tearDown(() => RouteMap.tileProviderFactory = RouteMap.defaultTileProvider);

    final cards = find.byType(EventCard);

    // AC3 (intent 0012): real EventCards per row.
    for (final width in [390.0, 744.0, 1280.0, 1920.0]) {
      testWidgets('real cards per row at $width dp', (tester) async {
        setSurface(tester, width, 3000);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final perRow = cardsPerRow(tester, cards);
        if (width == 390) expect(perRow, 1);
        if (width == 744) expect(perRow, 2);
        if (width == 1280) expect(perRow, 3);
        if (width == 1920) expect(perRow, greaterThanOrEqualTo(3));
        await unmount(tester);
      });
    }

    // AC4 (intent 0012): real cards never exceed maxCardWidth; centred.
    for (final width in [1920.0, 3840.0]) {
      testWidgets('real cards capped and centred at $width dp', (tester) async {
        setSurface(tester, width, 2000);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        final rects = rectsOf(tester, cards);
        expect(rects, isNotEmpty);
        for (final r in rects) {
          expect(r.width, lessThanOrEqualTo(ResponsiveCardGrid.maxCardWidth));
        }
        final area = rects.reduce((a, b) => a.expandToInclude(b));
        expect(area.width, lessThanOrEqualTo(ResponsiveCardGrid.maxBodyWidth));
        expect(area.left, moreOrLessEquals(width - area.right, epsilon: 0.5));
        await unmount(tester);
      });
    }

    // AC7 (intent 0012): the header is a full-width block above the grid.
    for (final width in [390.0, 744.0, 1280.0, 1920.0]) {
      testWidgets('header above every card, as wide as the grid ($width dp)',
          (tester) async {
        setSurface(tester, width, 3000);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        final header = tester.getRect(find.byKey(ResponsiveCardGrid.headerKey));
        expect(
            find.descendant(
                of: find.byKey(ResponsiveCardGrid.headerKey),
                matching: find.text('Update event data')),
            findsOneWidget);
        final rects = rectsOf(tester, cards);
        final area = rects.reduce((a, b) => a.expandToInclude(b));
        for (final r in rects) {
          expect(header.top, lessThan(r.top));
          expect(header.bottom, lessThanOrEqualTo(r.top));
        }
        expect(header.width, greaterThanOrEqualTo(area.width - 0.01));
        await unmount(tester);
      });
    }

    // AC7 (intent 0012): the button still triggers a refresh. The client
    // records the request and answers 404, so nothing leaves the test.
    testWidgets('"Update event data" still requests the event feed',
        (tester) async {
      final requested = <Uri>[];
      await http.runWithClient(() async {
        setSurface(tester, 1280);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        await tester.tap(find.text('Update event data'));
        await tester.pump();
        expect(find.textContaining('Updating events for'), findsOneWidget);
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(requested.where((u) => u.path.contains('scheduled_events')),
            isNotEmpty);
        await unmount(tester);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 10));
      },
          () => MockClient((request) async {
                requested.add(request.url);
                return http.Response('not here', 404);
              }));
    });

    // AC10 (intent 0012): intents 0010 and 0011 still hold in the
    // narrower card.
    for (final width in [744.0, 1280.0]) {
      testWidgets('map keeps its aspect ratio at $width dp', (tester) async {
        setSurface(tester, width, 3000);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        final maps = find.byType(RouteMap);
        expect(maps, findsWidgets);
        for (final e in maps.evaluate()) {
          final size = tester.getSize(find.byWidget(e.widget));
          expect(size.width / size.height,
              moreOrLessEquals(RouteMap.aspectRatio, epsilon: 0.01));
        }
        // Every tile layer uses the fake provider.
        for (final layer
            in tester.widgetList<TileLayer>(find.byType(TileLayer))) {
          expect(layer.tileProvider, isA<FakeTileProvider>());
        }
        await unmount(tester);
      });
    }

    // AC10 (intent 0012): off-screen cards are built lazily, so their tiles
    // are never requested.
    testWidgets('off-screen cards and their tiles are not built',
        (tester) async {
      setSurface(tester, 744, 500);
      await tester.pumpWidget(app(eventList()));
      await tester.pump();
      final built = find.byType(RouteMap, skipOffstage: false);
      final builtCount = built.evaluate().length;
      expect(builtCount, greaterThan(0));
      expect(builtCount, lessThan(events.length),
          reason: 'cards far below the fold should not be built');
      expect(providers.length, builtCount);
      await unmount(tester);
    });

    // AC10 (intent 0012): tapping a card map opens the full-screen map.
    testWidgets('tapping a map in the grid opens RouteMapPage', (tester) async {
      setSurface(tester, 1280);
      await tester.pumpWidget(app(eventList()));
      await tester.pump();
      await tester.tap(find.byType(RouteMap).first);
      await tester.pumpAndSettle();
      expect(find.byType(RouteMapPage), findsOneWidget);
      await unmount(tester);
    });
  });

  // AC7 (intent 0002), AC10 (intent 0009), AC11 (intent 0010): cards now
  // include the route map, drawn with a fake tile provider.
  // AC11 (intent 0012): at the three grid widths, light and dark.
  for (final width in [390.0, 744.0, 1280.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
          'event list meets contrast and tap-target guidelines '
          '($mode, $width dp)', (tester) async {
        setSurface(tester, width);
        final providers = <FakeTileProvider>[];
        RouteMap.tileProviderFactory = () {
          final p = FakeTileProvider();
          providers.add(p);
          return p;
        };
        addTearDown(
            () => RouteMap.tileProviderFactory = RouteMap.defaultTileProvider);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(app(eventList(), mode: mode));
        await tester.pump();
        expect(find.byType(EventCard), findsWidgets);
        expect(find.byType(RouteMap), findsWidgets);
        // Every map uses the fake provider: no network.
        final layers = tester.widgetList<TileLayer>(find.byType(TileLayer));
        expect(layers, isNotEmpty);
        for (final layer in layers) {
          expect(layer.tileProvider, isA<FakeTileProvider>());
        }
        expect(providers, isNotEmpty);
        // AC8 (intent 0011): the card maps are now tap targets too.
        expect(
            find.bySemanticsLabel(RouteMap.openFullScreenLabel), findsWidgets);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
        await unmount(tester);
      });
    }
  }
}
