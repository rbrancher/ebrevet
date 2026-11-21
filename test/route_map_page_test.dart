// Full-screen route map page (intent 0011, slice c).
//
// Every map here uses a fake TileProvider (test/support/fake_tiles.dart) or
// a recording http client; nothing touches the network.

import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/control.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/route_map_page.dart';
import 'package:ebrevet_card/route_sketch.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, unmount;
import 'route_map_test.dart' show tileCorner;
import 'support/fake_tiles.dart';
import 'support/fixtures.dart';

Control control(int i, double lat, double long,
        {String? name, String style = 'staffed', String address = ''}) =>
    Control.fromMap(i, {
      'dist_mi': i * 10,
      'lat': lat,
      'long': long,
      'name': name ?? 'Control number $i',
      'style': style,
      'address': address,
      'open': '2026-06-01T09:00:00+00:00',
      'close': '2026-06-01T10:00:00+00:00',
    });

/// A copy of [base] with [controls] in place of its own.
Event withControls(Event base, List<Control> controls) {
  final e = Event.fromJson(
      jsonDecode(jsonEncode(base.toJson)) as Map<String, dynamic>);
  e.controls
    ..clear()
    ..addAll(controls);
  return e;
}

/// Point to point, well spread so the markers do not overlap.
List<Control> lineControls() => [
      control(0, 40.0, -75.2, name: 'Start bakery', address: '1 Main St'),
      control(1, 40.5, -74.8,
          name: 'Photo of the covered bridge', style: 'photo'),
      control(2, 41.0, -74.4, name: 'Finish diner', address: '9 End Rd'),
    ];

Widget pageApp(Event event,
        {TileProvider? provider, ThemeMode mode = ThemeMode.light}) =>
    app(RouteMapPage(event: event, tileProvider: provider), mode: mode);

MapCamera cameraOf(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(RouteOverlay)));

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late List<Event> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MySetting.initSharedPreferences();
    useMockServerForTests();
    MockServer.now = DateTime.now;
    events = await mockEvents();
    ScheduledEvents.events = events;
  });

  tearDown(() {
    ScheduledEvents.events = <Event>[];
    MockServer.now = DateTime.now;
    MockServer.passthrough = null;
    RouteMap.tileProviderFactory = RouteMap.defaultTileProvider;
  });

  // AC1 (intent 0011)
  testWidgets('app bar with event name and distance, back button',
      (tester) async {
    final event = events.first;
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RouteMapPage(
                      event: event, tileProvider: FakeTileProvider()))),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final bar = find.byType(AppBar);
    expect(bar, findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text(event.nameDist)),
        findsOneWidget);
    expect(event.nameDist, contains('${event.distance}K'));
    expect(find.byType(BackButton), findsOneWidget);
    // The map fills the body below the app bar.
    expect(tester.getRect(find.byType(FlutterMap)).top,
        tester.getRect(bar).bottom);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(RouteMapPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
    await unmount(tester);
  });

  // AC1 (intent 0011)
  testWidgets('reuses the slice (a)/(b) overlay, tile layer and attribution',
      (tester) async {
    await tester
        .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
    expect(find.byType(RouteOverlay), findsOneWidget);
    expect(find.byType(MapAttributionChip), findsOneWidget);
    final p = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(RouteOverlay), matching: find.byType(CustomPaint)))
        .painter;
    expect(p, isA<RouteSketchPainter>());
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, RouteMap.tileUrlTemplate);
    expect(layer.tileProvider.headers['User-Agent'],
        'flutter_map (${RouteMap.userAgentPackageName})');
    // No duplicated constants, painter or attribution in the page source.
    final src = File('lib/route_map_page.dart').readAsStringSync();
    expect(src, isNot(contains('openstreetmap.org')));
    expect(src, isNot(contains('OpenStreetMap contributors')));
    expect(src, isNot(contains('CustomPainter')));
    expect(src, isNot(contains('TileLayer(')));
    await unmount(tester);
  });

  // AC2 (intent 0011)
  testWidgets('interactive: pan and zoom, no rotation, zoom 3 to 19',
      (tester) async {
    await tester
        .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    final flags = options.interactionOptions.flags;
    expect(flags, RouteMapPage.interactionFlags);
    for (final f in [
      InteractiveFlag.drag,
      InteractiveFlag.pinchZoom,
      InteractiveFlag.scrollWheelZoom,
      InteractiveFlag.doubleTapZoom,
    ]) {
      expect(InteractiveFlag.hasFlag(flags, f), isTrue);
    }
    expect(InteractiveFlag.hasFlag(flags, InteractiveFlag.rotate), isFalse);
    expect(options.minZoom, 3);
    expect(options.maxZoom, 19);
    expect(RouteMap.minZoom, 3);
    expect(RouteMap.maxZoom, 19);
    expect(
        find.byType(IgnorePointer).evaluate().where((e) {
          final w = e.widget as IgnorePointer;
          return w.ignoring &&
              find
                  .descendant(
                      of: find.byWidget(w), matching: find.byType(FlutterMap))
                  .evaluate()
                  .isNotEmpty;
        }),
        isEmpty);

    // A drag pans the map.
    await tester.pump();
    final before = cameraOf(tester).center;
    await tester.timedDragFrom(tester.getCenter(find.byType(FlutterMap)),
        const Offset(-120, 80), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(cameraOf(tester).center, isNot(before));
    expect(cameraOf(tester).rotation, 0);
    await unmount(tester);
  });

  // AC2 (intent 0011)
  testWidgets('initial view: same fit as the card, every control in view',
      (tester) async {
    for (final event in [
      ...events,
      withControls(events.first, lineControls()),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
      final geometry = RouteGeometry.fromLatLongs(
          event.controls.map((c) => LatLong(c.lat, c.long)));
      if (!geometry.isDrawable) continue;
      final camera = cameraOf(tester);
      final size = tester.getSize(find.byType(FlutterMap));
      // The card's fit (same padded bounds, RouteMap.cameraFitOf), with
      // room kept for the marker labels.
      final fitted = RouteMap.fittedCamera(geometry, size,
          padding: RouteMapPage.markerPadding);
      expect(camera.center, fitted.center);
      expect(camera.zoom, closeTo(fitted.zoom, 1e-9));
      for (final p in geometry.latLongs) {
        expect(camera.visibleBounds.contains(LatLng(p.lat, p.long)), isTrue,
            reason: 'control $p of ${event.name} outside the initial view');
      }
      await tester.pump();
      for (final p in geometry.latLongs) {
        expect(cameraOf(tester).visibleBounds.contains(LatLng(p.lat, p.long)),
            isTrue);
      }
      // Every marker label starts fully inside the map.
      final mapRect = tester.getRect(find.byType(FlutterMap));
      for (final m in find.byType(ControlMarker).evaluate()) {
        final r = tester.getRect(find.descendant(
            of: find.byWidget(m.widget),
            matching: find.byType(GestureDetector)));
        expect(mapRect.intersect(r), r,
            reason: 'marker clipped in ${event.name}');
      }
    }
    await unmount(tester);
  });

  // AC3 (intent 0011)
  testWidgets('every usable control has a named marker with a 48 dp target',
      (tester) async {
    final handle = tester.ensureSemantics();
    final event = withControls(
        events.first, [...events.first.controls, control(9, 0, 0)]);
    await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
    final usable = RouteMapPage.usableControls(event.controls);
    expect(usable.length, event.controls.length - 1);
    final markers = find.byType(ControlMarker);
    expect(markers, findsNWidgets(usable.length));
    for (final c in usable) {
      final marker = find.byWidgetPredicate(
          (w) => w is ControlMarker && identical(w.control, c));
      expect(marker, findsOneWidget);
      expect(find.descendant(of: marker, matching: find.text(c.name)),
          findsOneWidget);
      expect(find.bySemanticsLabel(c.name), findsWidgets);
      final target =
          find.descendant(of: marker, matching: find.byType(GestureDetector));
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    // Long names are truncated on the marker, never wrapped.
    for (final t in tester.widgetList<Text>(
        find.descendant(of: markers, matching: find.byType(Text)))) {
      expect(t.maxLines, 1);
      expect(t.overflow, TextOverflow.ellipsis);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
    await unmount(tester);
  });

  // AC3 (intent 0011)
  testWidgets('tapping a marker shows name, address and times if timed',
      (tester) async {
    final event = withControls(events.first, lineControls());
    await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
    await tester.pump();

    await tester.tap(find.text('Start bakery'));
    await tester.pumpAndSettle();
    var sheet = find.byType(ControlDetailsSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Start bakery')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('1 Main St')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Open: ${event.openTimeString(0)}')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet,
            matching: find.text('Close: ${event.closeTimeString(0)}')),
        findsOneWidget);
    Navigator.of(tester.element(sheet)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ControlDetailsSheet), findsNothing);

    // An untimed (photo) control: name only, no times.
    await tester.tap(find.text('Photo of the covered bridge'));
    await tester.pumpAndSettle();
    sheet = find.byType(ControlDetailsSheet);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Photo of the covered bridge')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('Open:')),
        findsNothing);
    await unmount(tester);
  });

  // AC4 (intent 0011)
  testWidgets('tile provider: injected or the RouteMap seam; visible only',
      (tester) async {
    final fake = FakeTileProvider();
    await tester.pumpWidget(pageApp(events.first, provider: fake));
    var layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(identical(layer.tileProvider, fake), isTrue);
    expect(layer.panBuffer, lessThanOrEqualTo(1));
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(fake.requested, isNotEmpty);
    final view = cameraOf(tester).visibleBounds;
    for (final c in fake.requested) {
      final tile = LatLngBounds(
          tileCorner(c.x, c.y + 1, c.z), tileCorner(c.x + 1, c.y, c.z));
      expect(tile.isOverlapping(view), isTrue, reason: 'tile $c not in view');
    }

    final seam = FakeTileProvider();
    RouteMap.tileProviderFactory = () => seam;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(pageApp(events.first));
    layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(identical(layer.tileProvider, seam), isTrue);
    expect(seam.requested, isNotEmpty);
    await unmount(tester);
  });

  // AC5 (intent 0011)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('tiles fail: route, markers and attribution remain ($mode)',
        (tester) async {
      final failing = FakeTileProvider(fail: true);
      final event = events.first;
      await tester.pumpWidget(pageApp(event, provider: failing, mode: mode));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(failing.requested, isNotEmpty);
      final scheme =
          Theme.of(tester.element(find.byType(FlutterMap))).colorScheme;
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.backgroundColor, scheme.surfaceContainerHighest);
      final painter = tester
          .widget<CustomPaint>(find.descendant(
              of: find.byType(RouteOverlay),
              matching: find.byType(CustomPaint)))
          .painter! as RouteSketchPainter;
      expect(painter.screenPoints, isNotEmpty);
      expect(find.byType(ControlMarker),
          findsNWidgets(RouteMapPage.usableControls(event.controls).length));
      expect(find.text(RouteMap.attribution), findsOneWidget);
      await unmount(tester);
      expect(tester.takeException(), isNull);
    });
  }

  // AC8 (intent 0011)
  testWidgets('rotation and resizing: no overflow, map fills the body',
      (tester) async {
    final event = events.first;
    final provider = FakeTileProvider();
    for (final size in const [
      Size(400, 800),
      Size(800, 400),
      Size(320, 480),
      Size(1200, 900),
    ]) {
      await setSize(tester, size);
      await tester.pumpWidget(pageApp(event, provider: provider));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'at $size');
      final body = tester.getRect(find.byType(FlutterMap));
      expect(body.width, size.width);
      expect(body.bottom, size.height);
    }
    await unmount(tester);
  });

  // AC8 (intent 0011)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('page meets contrast and tap-target guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final provider = FakeTileProvider();
      await tester
          .pumpWidget(pageApp(events.first, provider: provider, mode: mode));
      await tester.pump();
      expect(find.byType(ControlMarker), findsWidgets);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // The details sheet too.
      await tester.tap(find.byType(ControlMarker).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      if (find.byType(ControlDetailsSheet).evaluate().isNotEmpty) {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      expect(provider.requested, isNotEmpty);
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC9 (intent 0011): with real network tiles routed through MockServer,
  // the only requests are tile GETs to the tile host; no check-in report.
  testWidgets('mock mode: only tile GETs to the tile host', (tester) async {
    final seen = <http.BaseRequest>[];
    final forwarded = <http.BaseRequest>[];
    MockServer.passthrough = MockClient((req) async {
      forwarded.add(req);
      return http.Response.bytes(transparentPng, 200,
          headers: {'content-type': 'image/png'});
    });
    final client = MockClient((req) async {
      seen.add(req);
      return MockServer.handle(req);
    });
    final provider = NetworkTileProvider(
        httpClient: client,
        cachingProvider: const DisabledMapCachingProvider());
    await tester.pumpWidget(pageApp(events.first, provider: provider));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(seen, isNotEmpty);
    for (final r in seen) {
      expect(r.method, 'GET');
      expect(r.url.host, RouteMap.tileHost);
    }
    expect(forwarded.length, seen.length);
    expect(MockServer.receivedReports, isEmpty);
    await unmount(tester);
    client.close();
  });

  // AC9 (intent 0011): the default under flutter test makes no requests.
  test('default tile provider under flutter test is NoTileProvider', () {
    expect(RouteMap.tileProviderFactory(), isA<NoTileProvider>());
  });

  // AC10 (intent 0011): the page touches no check-in, code, ride state or
  // reporting code.
  test('page does not use check-in, codes, ride state or reporting', () {
    final src = File('lib/route_map_page.dart').readAsStringSync();
    for (final f in [
      'checkin.dart',
      'signature.dart',
      'report.dart',
      'activated_event.dart',
      'my_activated_events.dart',
      'location.dart',
      'package:http',
    ]) {
      expect(src, isNot(contains(f)));
    }
  });
}
