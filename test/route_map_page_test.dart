// Full-screen route map page (intent 0011, slice c).
//
// Every map here uses a fake TileProvider (test/support/fake_tiles.dart) or
// a recording http client; nothing touches the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ebrevet_card/control.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/ride_summary_sheet.dart';
import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/route_map_page.dart';
import 'package:ebrevet_card/route_service.dart';
import 'package:ebrevet_card/route_sketch.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, eventList, unmount;
import 'route_map_test.dart' show tileCorner;
import 'support/fake_route_service.dart';
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

/// The tap target of the marker for the control named [name].
Finder markerTarget(String name) => find.descendant(
    of: find
        .byWidgetPredicate((w) => w is ControlMarker && w.control.name == name),
    matching: find.byType(GestureDetector));

/// The summary sheet's surface; its height is the visible extent.
Finder get sheetSurface => find.byKey(RideSummarySheet.surfaceKey);

/// The highlighted control in the summary sheet's list.
Finder get highlightedRow =>
    find.byWidgetPredicate((w) => w is ControlRow && w.highlighted);

/// Height of the page body (the area the sheet's sizes are fractions of).
double bodyHeight(WidgetTester tester) =>
    tester.getSize(find.byType(RideSummarySheet)).height;

/// Visible sheet extent as a fraction of the body.
double sheetSize(WidgetTester tester) =>
    tester.getSize(sheetSurface).height / bodyHeight(tester);

/// Taps the handle until the sheet is collapsed (it steps collapsed, half,
/// expanded).
Future<void> collapseSheet(WidgetTester tester) async {
  final collapsed = RideSummarySheet.collapsedSize(bodyHeight(tester));
  for (var i = 0; i < 3 && sheetSize(tester) > collapsed + 0.01; i++) {
    await tester.tap(find.bySemanticsLabel(RegExp('ride summary')));
    await tester.pumpAndSettle();
  }
  expect(sheetSize(tester), closeTo(collapsed, 0.01));
}

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

    // A drag above the (half-open) summary sheet pans the map.
    await tester.pump();
    final before = cameraOf(tester).center;
    final mapRect = tester.getRect(find.byType(FlutterMap));
    await tester.timedDragFrom(
        Offset(mapRect.center.dx, mapRect.top + mapRect.height / 4),
        const Offset(-120, 80),
        const Duration(milliseconds: 300));
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
      // room kept for the marker labels and (intent 0013) the summary
      // sheet, which opens at half height.
      final fitted = RouteMap.fittedCamera(geometry, size,
          padding: RouteMapPage.fitPadding(
              RideSummarySheet.initialExtent(size.height)));
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

  // AC3 (intent 0011), updated by AC7 (intent 0013): the details now show
  // in the persistent summary sheet, not a modal.
  testWidgets('tapping a marker shows name, address and times if timed',
      (tester) async {
    final event = withControls(events.first, lineControls());
    await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
    await tester.pump();

    await tester.tap(markerTarget('Start bakery'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlDetails), findsOneWidget);
    final sheet = highlightedRow;
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

    // An untimed (photo) control: name only, no times.
    await tester.tap(markerTarget('Photo of the covered bridge'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlDetails), findsOneWidget);
    expect(sheet, findsOneWidget);
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
      // The highlighted control in the summary sheet too (intent 0013).
      await tester.tap(find.byType(ControlMarker).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      if (find.byType(ControlDetails).evaluate().isNotEmpty) {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
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
  // AC10 (intent 0011) and AC12 (intent 0013): neither the page nor the
  // summary sheet touches check-in, codes, ride state, reporting, location
  // or the network.
  test('page does not use check-in, codes, ride state or reporting', () {
    for (final path in [
      'lib/route_map_page.dart',
      'lib/ride_summary_sheet.dart',
    ]) {
      final src = File(path).readAsStringSync();
      for (final f in [
        'checkin.dart',
        'signature.dart',
        'report.dart',
        'activated_event.dart',
        'my_activated_events.dart',
        'location.dart',
        'geolocator',
        'package:http',
      ]) {
        expect(src, isNot(contains(f)), reason: '$path uses $f');
      }
    }
  });

  group('ride summary sheet (intent 0013)', () {
    // AC1 (intent 0013), refined on PR 41: the sheet opens at half height,
    // and its title is styled as on the event card.
    testWidgets('persistent sheet, opens at half, name, distance and start',
        (tester) async {
      final event = events.first;
      await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
      await tester.pump();
      final page = find.byType(RouteMapPage);
      final sheet = find.descendant(
          of: page, matching: find.byType(DraggableScrollableSheet));
      expect(sheet, findsOneWidget);
      // Inside the page body, over the map, not a modal route.
      expect(find.byType(BottomSheet), findsNothing);
      expect(Navigator.of(tester.element(page)).canPop(), isFalse);
      final body = tester.getRect(find.byType(RideSummarySheet));
      expect(tester.getRect(find.byType(FlutterMap)), body);
      final surface = tester.getRect(sheetSurface);
      expect(surface.bottom, body.bottom);
      expect(tester.widget<DraggableScrollableSheet>(sheet).snap, isTrue);
      // Opens at half height, with a drag handle.
      expect(surface.height,
          closeTo(RideSummarySheet.initialExtent(body.height), 0.5));
      expect(
          find.bySemanticsLabel(RideSummarySheet.expandLabel), findsOneWidget);
      // The title is the card's: name and distance, titleLarge, bold.
      final title = find.descendant(
          of: sheetSurface, matching: find.text(event.nameDist));
      final textTheme = Theme.of(tester.element(title)).textTheme;
      final style = tester.widget<Text>(title).style!;
      expect(style.fontSize, textTheme.titleLarge!.fontSize);
      expect(style.fontWeight, FontWeight.w700);
      expect(event.nameDist, contains('${event.distance}K'));
      // Collapsed content is inside the visible part of the collapsed sheet.
      await collapseSheet(tester);
      final collapsed = tester.getRect(sheetSurface);
      expect(collapsed.height,
          closeTo(RideSummarySheet.collapsedExtent(body.height), 0.5));
      for (final text in [
        title,
        find.descendant(
            of: sheetSurface,
            matching: find.text(RideSummarySheet.startText(event))),
      ]) {
        expect(text, findsOneWidget);
        final r = tester.getRect(text);
        expect(collapsed.intersect(r), r);
      }
      expect(RideSummarySheet.startText(event), contains(event.dateTime));
      await unmount(tester);
    });

    // AC2 (intent 0013)
    testWidgets('drags snap between collapsed, half and expanded',
        (tester) async {
      await setSize(tester, const Size(400, 700));
      await tester
          .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
      await tester.pump();
      final h = bodyHeight(tester);
      final collapsed = RideSummarySheet.collapsedSize(h);
      final handle = find.bySemanticsLabel(RegExp('ride summary'));
      // A slow drag from the current size to [to] (a fraction of the body);
      // the sheet then snaps.
      Future<void> drag(double to) async {
        await tester.timedDrag(handle, Offset(0, (sheetSize(tester) - to) * h),
            const Duration(seconds: 1));
        await tester.pumpAndSettle();
      }

      // Three stops: collapsed, half and three quarters (PR 41).
      expect(RideSummarySheet.expandedSize, 0.75);
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      // Down near the bottom: snaps to collapsed.
      await drag(collapsed + 0.06);
      expect(sheetSize(tester), closeTo(collapsed, 0.01));
      // Up to just below half: snaps to half.
      await drag(0.42);
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      // Up most of the way: snaps to expanded.
      await drag(0.71);
      expect(sheetSize(tester), closeTo(RideSummarySheet.expandedSize, 0.01));
      // Expanded content scrolls, with no overflow.
      final scroll =
          find.descendant(of: sheetSurface, matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scroll.first).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.timedDrag(
          find.text('${events.first.controls.length} controls'),
          const Offset(0, -200),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(sheetSize(tester), closeTo(RideSummarySheet.expandedSize, 0.01));
      expect(tester.takeException(), isNull);
      position.jumpTo(0);
      await tester.pump();
      // Down: back to half, then collapsed.
      await drag(0.55);
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      await drag(collapsed + 0.06);
      expect(sheetSize(tester), closeTo(collapsed, 0.01));
      await unmount(tester);
    });

    // AC3 (intent 0013), refined on PR 41: a tap steps through the three
    // stops (collapsed, half, expanded) and back to collapsed.
    testWidgets('tapping the handle steps the sheet; 48 dp, labelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
      await tester.pump();
      final collapsed = RideSummarySheet.collapsedSize(bodyHeight(tester));
      final expand = find.bySemanticsLabel(RideSummarySheet.expandLabel);
      expect(
          tester.getSemantics(expand),
          matchesSemantics(
              label: RideSummarySheet.expandLabel,
              isButton: true,
              hasTapAction: true));
      final target = tester.getSemantics(expand).rect;
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.width, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      // Opens at half; half to expanded.
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(sheetSize(tester), closeTo(RideSummarySheet.expandedSize, 0.01));
      final collapse = find.bySemanticsLabel(RideSummarySheet.collapseLabel);
      expect(collapse, findsOneWidget);
      expect(
          tester.getSemantics(collapse),
          matchesSemantics(
              isButton: true,
              hasTapAction: true,
              label: RideSummarySheet.collapseLabel));
      // Expanded back to collapsed.
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(sheetSize(tester), closeTo(collapsed, 0.01));
      // Collapsed to half.
      await tester.tap(find.bySemanticsLabel(RideSummarySheet.expandLabel));
      await tester.pumpAndSettle();
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      // The semantics tap action steps too.
      tester.semantics
          .tap(find.semantics.byLabel(RideSummarySheet.expandLabel));
      await tester.pumpAndSettle();
      expect(sheetSize(tester), closeTo(RideSummarySheet.expandedSize, 0.01));
      handle.dispose();
      await unmount(tester);
    });

    // AC4 (intent 0013), refined on PR 41: fitted above the sheet as it
    // opens (half height).
    testWidgets('route fitted above the opening sheet; map still pans',
        (tester) async {
      for (final size in const [
        Size(800, 600),
        Size(400, 800),
        Size(800, 400)
      ]) {
        await setSize(tester, size);
        for (final event in [
          ...events,
          withControls(events.first, lineControls()),
        ]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
          await tester.pump();
          final geometry = RouteGeometry.fromLatLongs(
              event.controls.map((c) => LatLong(c.lat, c.long)));
          if (!geometry.isDrawable) continue;
          final mapSize = tester.getSize(find.byType(FlutterMap));
          final inset = RideSummarySheet.initialExtent(mapSize.height);
          final camera = cameraOf(tester);
          final fitted = RouteMap.fittedCamera(geometry, mapSize,
              padding: RouteMapPage.fitPadding(inset));
          expect(camera.center, fitted.center);
          expect(camera.zoom, closeTo(fitted.zoom, 1e-9));
          // Every usable control and its marker lies above the sheet.
          final sheetTop = tester.getRect(sheetSurface).top;
          final mapRect = tester.getRect(find.byType(FlutterMap));
          final visible =
              Rect.fromLTRB(mapRect.left, mapRect.top, mapRect.right, sheetTop);
          expect(sheetTop, closeTo(mapRect.bottom - inset, 0.5));
          for (final c in RouteMapPage.usableControls(event.controls)) {
            final p = camera.latLngToScreenOffset(LatLng(c.lat, c.long)) +
                mapRect.topLeft;
            expect(visible.contains(p), isTrue,
                reason: '${c.name} of ${event.name} behind the sheet at $size');
          }
          for (final m in find.byType(ControlMarker).evaluate()) {
            final r = tester.getRect(find.descendant(
                of: find.byWidget(m.widget),
                matching: find.byType(GestureDetector)));
            expect(visible.intersect(r), r,
                reason: 'marker hidden in ${event.name} at $size');
          }
        }
      }

      // A drag in the area above the sheet pans the map.
      await setSize(tester, const Size(800, 600));
      await tester.pumpWidget(const SizedBox());
      await tester
          .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
      await tester.pump();
      final before = cameraOf(tester).center;
      final mapRect = tester.getRect(find.byType(FlutterMap));
      await tester.timedDragFrom(mapRect.topLeft + const Offset(30, 30),
          const Offset(80, 60), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(cameraOf(tester).center, isNot(before));
      expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
      await unmount(tester);
    });

    // AC7 (intent 0013)
    testWidgets('tapping a marker expands the sheet to the control, no modal',
        (tester) async {
      final event = withControls(events.first, [
        for (var i = 0; i < 12; i++)
          control(i, 40.0 + i * 0.1, -75.2 + i * 0.1,
              name: 'Stop $i', address: '$i Road'),
      ]);
      // Tall enough that the twelve markers above the half-open sheet do
      // not overlap.
      await setSize(tester, const Size(800, 1400));
      await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
      await tester.pump();
      final page = find.byType(RouteMapPage);
      await tester.tap(markerTarget('Stop 11'));
      await tester.pumpAndSettle();
      // No modal route, no second sheet.
      expect(Navigator.of(tester.element(page)).canPop(), isFalse);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      // At least half, scrolled to the highlighted control.
      expect(sheetSize(tester),
          greaterThanOrEqualTo(RideSummarySheet.halfSize - 0.01));
      final rows = tester.widgetList<ControlRow>(find.byType(ControlRow));
      expect(rows.where((r) => r.highlighted).map((r) => r.control.name),
          ['Stop 11']);
      expect(find.byType(ControlDetails), findsOneWidget);
      final details = highlightedRow;
      for (final t in [
        'Stop 11',
        '11 Road',
        'Open: ${ControlDetails.timeString(event.controls[11].open)}',
        'Close: ${ControlDetails.timeString(event.controls[11].close)}',
      ]) {
        expect(find.descendant(of: details, matching: find.text(t)),
            findsOneWidget);
      }
      final sheet = tester.getRect(sheetSurface);
      final r = tester.getRect(details);
      expect(sheet.intersect(r), r, reason: 'highlighted row not in view');

      // Collapsed again, another marker moves the highlight; still one
      // sheet.
      await collapseSheet(tester);
      await tester.tap(markerTarget('Stop 0'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ControlRow>(find.byType(ControlRow))
              .where((r) => r.highlighted)
              .map((r) => r.control.name),
          ['Stop 0']);
      expect(sheet.intersect(tester.getRect(find.byType(ControlDetails))),
          tester.getRect(find.byType(ControlDetails)));
      expect(Navigator.of(tester.element(page)).canPop(), isFalse);

      // Collapsed, the same marker again: the sheet expands again.
      await collapseSheet(tester);
      expect(sheetSize(tester), lessThan(RideSummarySheet.halfSize));
      await tester.tap(markerTarget('Stop 0'));
      await tester.pumpAndSettle();
      expect(sheetSize(tester),
          greaterThanOrEqualTo(RideSummarySheet.halfSize - 0.01));
      await unmount(tester);
    });

    // AC8 (intent 0013)
    testWidgets('tapping a control in the list centres the map on it',
        (tester) async {
      final event = withControls(events.first, lineControls());
      await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(RideSummarySheet.expandLabel));
      await tester.pumpAndSettle();
      final zoomBefore = cameraOf(tester).zoom;
      final target = event.controls[1];
      final row = find.byWidgetPredicate(
          (w) => w is ControlRow && identical(w.control, target));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      final camera = cameraOf(tester);
      expect(camera.zoom,
          closeTo(max(zoomBefore, RouteMapPage.minFocusZoom), 1e-9));
      // Centred in the part of the map above the sheet.
      final map = tester.getRect(find.byType(FlutterMap));
      final sheetTop = tester.getRect(sheetSurface).top;
      final expected = Offset(map.width / 2, (sheetTop - map.top) / 2);
      final p = camera.latLngToScreenOffset(LatLng(target.lat, target.long));
      expect(p.dx, closeTo(expected.dx, 1));
      expect(p.dy, closeTo(expected.dy, 1));
      // The camera centre is the control shifted by half the sheet.
      final centre = camera.latLngToScreenOffset(camera.center);
      expect(centre.dy - p.dy, closeTo((map.bottom - sheetTop) / 2, 1));
      expect(tester.widget<ControlRow>(row).highlighted, isTrue);
      expect(find.byType(ControlDetails), findsOneWidget);
      await unmount(tester);
    });

    // AC10 (intent 0013)
    testWidgets('sheet in semantics, in reading order; attribution visible',
        (tester) async {
      final handle = tester.ensureSemantics();
      await setSize(tester, const Size(500, 1600));
      final event = withControls(events.first, lineControls());
      await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
      await tester.pump();
      // The attribution chip follows the top of the sheet: above it as it
      // opens, collapsed and expanded.
      void expectChipAboveSheet() {
        final top = tester.getRect(sheetSurface).top;
        final chip = tester.getRect(find.byType(MapAttributionChip).last);
        final text = tester.getRect(find.text(RouteMap.attribution));
        expect(text.bottom, lessThanOrEqualTo(top));
        expect(chip.bottom, lessThanOrEqualTo(top));
        expect(chip.bottom, greaterThan(top - 40));
      }

      expectChipAboveSheet();
      await collapseSheet(tester);
      expectChipAboveSheet();

      await tester.timedDrag(
          find.bySemanticsLabel(RideSummarySheet.expandLabel),
          const Offset(0, -1400),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expectChipAboveSheet();
      final labels = [
        for (final n in tester.semantics.simulatedAccessibilityTraversal())
          n.label
      ];
      // The map (app bar, attribution, markers) comes first, then the sheet.
      final start = labels.indexOf(RideSummarySheet.collapseLabel);
      expect(start, greaterThan(0), reason: '$labels');
      expect(labels.indexOf(RouteMap.attribution), lessThan(start));
      int at(String label) =>
          labels.indexWhere((l) => l.contains(label), start);
      final order = [
        start,
        at(event.nameDist),
        at(RideSummarySheet.startText(event)),
        at('Ride details'),
        at('Club:'),
        at('${event.controls.length} controls'),
        for (final c in event.controls)
          labels.lastIndexWhere((l) => l.contains(c.name)),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)), reason: '$labels');
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]), reason: '$labels');
      }
      handle.dispose();
      await unmount(tester);
    });

    // AC11 (intent 0013)
    testWidgets('non-drawable route: no map, the summary still shows',
        (tester) async {
      for (final controls in [
        [control(0, 40.0, -75.2, name: 'Only control')],
        [control(0, 0, 0, name: 'Nowhere'), control(1, 0, 0)],
      ]) {
        final event = withControls(events.first, controls);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
        await tester.pump();
        expect(find.byType(FlutterMap), findsNothing);
        expect(find.byType(RouteSketch), findsOneWidget);
        expect(find.byType(RideSummarySheet), findsOneWidget);
        expect(
            find.descendant(
                of: sheetSurface, matching: find.text(event.nameDist)),
            findsOneWidget);
        expect(sheetSize(tester), closeTo(RideSummarySheet.halfSize, 0.01));
        final row = find.byType(ControlRow).first;
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byType(ControlDetails), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await unmount(tester);
    });

    // AC9 (intent 0013): no overflow on rotation or resize, at any extent.
    testWidgets('rotation and resize with the sheet expanded: no overflow',
        (tester) async {
      for (final size in const [
        Size(400, 800),
        Size(800, 400),
        Size(320, 480),
        Size(480, 320),
        Size(1200, 900),
      ]) {
        await setSize(tester, size);
        await tester
            .pumpWidget(pageApp(events.first, provider: FakeTileProvider()));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at $size');
        final collapse = find.bySemanticsLabel(RideSummarySheet.collapseLabel);
        if (collapse.evaluate().isEmpty) {
          await tester.tap(find.bySemanticsLabel(RideSummarySheet.expandLabel));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: 'at $size');
        expect(tester.getRect(sheetSurface).bottom, size.height);
      }
      await unmount(tester);
    });

    // AC12 (intent 0013): opening the page and using the sheet posts
    // nothing.
    testWidgets('no requests or reports from the sheet', (tester) async {
      final requests = <http.BaseRequest>[];
      await http.runWithClient(() async {
        final event = withControls(events.first, lineControls());
        await tester.pumpWidget(pageApp(event, provider: FakeTileProvider()));
        await tester.pump();
        await tester.tap(markerTarget('Finish diner'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(ControlRow).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ControlRow).first);
        await tester.pumpAndSettle();
      },
          () => MockClient((req) async {
                requests.add(req);
                return http.Response('', 500);
              }));
      expect(requests, isEmpty);
      expect(MockServer.receivedReports, isEmpty);
      await unmount(tester);
    });
  });

  group('real route (intent 0014)', () {
    late FakeRouteService fake;

    setUp(() {
      fake = FakeRouteService();
      RouteService.factory = () => fake;
    });

    tearDown(() {
      RouteService.factory = RouteService.defaultService;
      RouteService.cache.clear();
    });

    /// The fixture's first event without a feed route.
    Event unrouted() => events.firstWhere((e) => e.route == null);

    List<LatLong> usable(Event e) => [
          for (final c in RouteMapPage.usableControls(e.controls))
            LatLong(c.lat, c.long)
        ];

    RouteOverlay overlay(WidgetTester tester) =>
        tester.widget<RouteOverlay>(find.byType(RouteOverlay));

    RouteSketchPainter painter(WidgetTester tester) => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(RouteOverlay), matching: find.byType(CustomPaint)))
        .painter! as RouteSketchPainter;

    Widget page(Event event,
            {Duration timeout = RouteService.timeout,
            ThemeMode mode = ThemeMode.light}) =>
        app(
            RouteMapPage(
                event: event,
                tileProvider: FakeTileProvider(),
                routeTimeout: timeout),
            mode: mode);

    final approxLabel = find.text(RouteMapPage.approximateRouteLabel);
    final straightLabel = find.text(RouteMapPage.straightRouteLabel);

    void expectNoErrorUi(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    }

    // AC4 (intent 0014)
    testWidgets('feed route drawn in place of straight lines, no router call',
        (tester) async {
      final event = events.firstWhere((e) => e.route != null);
      await tester.pumpWidget(page(event));
      await tester.pump();
      expect(overlay(tester).route, event.route);
      final p = painter(tester);
      expect(p.routePoints, hasLength(event.route!.length));
      final camera = cameraOf(tester);
      for (var i = 0; i < event.route!.length; i++) {
        final r = event.route![i];
        expect(p.routePoints![i],
            camera.latLngToScreenOffset(LatLng(r.lat, r.long)));
      }
      // Start/finish markers and casing are drawn by the same painter, on
      // the control points, and the named markers are a layer above.
      expect(p.screenPoints, hasLength(usable(event).length));
      expect(p.markers, isNotEmpty);
      expect(p.casing, isNot(p.line));
      final children =
          tester.widget<FlutterMap>(find.byType(FlutterMap)).children;
      expect(children.indexWhere((w) => w is MarkerLayer),
          greaterThan(children.indexWhere((w) => w is RouteOverlay)));
      expect(find.byType(ControlMarker), findsNWidgets(usable(event).length));
      expect(fake.calls, 0);
      expect(approxLabel, findsNothing);
      expect(straightLabel, findsNothing);
      await unmount(tester);
    });

    // AC7 (intent 0014)
    testWidgets('routed fallback: drawn, labelled approximate, one call',
        (tester) async {
      final handle = tester.ensureSemantics();
      final event = unrouted();
      await tester.pumpWidget(page(event));
      await tester.pump();
      expect(fake.calls, 1);
      expect(fake.requests.single, usable(event));
      expect(overlay(tester).route, FakeRouteService.wiggle(usable(event)));
      expect(painter(tester).routePoints,
          hasLength(overlay(tester).route!.length));
      expect(approxLabel, findsOneWidget);
      expect(find.bySemanticsLabel(RouteMapPage.approximateRouteSemantics),
          findsOneWidget);
      expect(RouteMapPage.approximateRouteSemantics,
          'approximate road route; may differ from the official course');
      expect(straightLabel, findsNothing);
      // Rebuilds and sheet use do not ask again.
      await collapseSheet(tester);
      await tester.pumpAndSettle();
      expect(fake.calls, 1);
      handle.dispose();
      await unmount(tester);
    });

    // AC8 (intent 0014)
    testWidgets('cache: reopening the same event makes no second call',
        (tester) async {
      final event = unrouted();
      await tester.pumpWidget(page(event));
      await tester.pump();
      await unmount(tester);
      await tester.pumpWidget(page(event));
      // Drawn from the first frame, no request.
      expect(overlay(tester).route, isNotNull);
      expect(approxLabel, findsOneWidget);
      await tester.pump();
      expect(fake.calls, 1);
      await unmount(tester);
      // A changed control set asks again.
      await tester.pumpWidget(page(withControls(event, lineControls())));
      await tester.pump();
      expect(fake.calls, 2);
      await unmount(tester);
    });

    // AC8 (intent 0014)
    testWidgets('failures are not cached: a later reopen retries',
        (tester) async {
      fake.answer = (c) async => null;
      final event = unrouted();
      await tester.pumpWidget(page(event));
      await tester.pump();
      expect(straightLabel, findsOneWidget);
      await unmount(tester);
      fake.answer = (c) async => FakeRouteService.wiggle(c);
      await tester.pumpWidget(page(event));
      await tester.pump();
      expect(fake.calls, 2);
      expect(approxLabel, findsOneWidget);
      await unmount(tester);
    });

    // AC9 (intent 0014)
    final failures = <String, Future<List<LatLong>?> Function(List<LatLong>)>{
      'null': (c) async => null,
      'throw': (c) async => throw const SocketException('offline'),
      'one point': (c) async => [c.first],
    };
    for (final f in failures.entries) {
      testWidgets('router ${f.key}: straight lines, subtle label, no error',
          (tester) async {
        final handle = tester.ensureSemantics();
        fake.answer = f.value;
        await tester.pumpWidget(page(unrouted()));
        await tester.pump();
        expect(overlay(tester).route, isNull);
        expect(painter(tester).routePoints, isNull);
        expect(straightLabel, findsOneWidget);
        expect(find.bySemanticsLabel(RouteMapPage.straightRouteLabel),
            findsOneWidget);
        expect(approxLabel, findsNothing);
        expectNoErrorUi(tester);
        handle.dispose();
        await unmount(tester);
      });
    }

    // AC9 (intent 0014)
    testWidgets('timeout: straight lines; no label while in flight',
        (tester) async {
      fake.answer = (c) => Completer<List<LatLong>?>().future;
      await tester.pumpWidget(
          page(unrouted(), timeout: const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
      // In flight: straight lines, no label of either kind.
      expect(overlay(tester).route, isNull);
      expect(find.byType(RouteOverlay), findsOneWidget);
      expect(straightLabel, findsNothing);
      expect(approxLabel, findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(straightLabel, findsOneWidget);
      expect(overlay(tester).route, isNull);
      expectNoErrorUi(tester);
      await unmount(tester);
    });

    // AC9 (intent 0014)
    testWidgets('a response after the page is disposed does nothing',
        (tester) async {
      final pending = Completer<List<LatLong>?>();
      fake.answer = (c) => pending.future;
      final event = unrouted();
      await tester.pumpWidget(page(event));
      await tester.pump();
      await unmount(tester);
      pending.complete(FakeRouteService.wiggle(usable(event)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(RouteMapPage), findsNothing);
    });

    // AC10 (intent 0014)
    testWidgets('cards and list: straight sketch, zero router calls',
        (tester) async {
      await tester.pumpWidget(app(eventList()));
      await tester.pump();
      expect(find.byType(EventCard), findsWidgets);
      expect(find.byType(RouteMap), findsWidgets);
      for (final o in find.byType(RouteOverlay).evaluate()) {
        expect((o.widget as RouteOverlay).route, isNull);
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      for (final o in find.byType(RouteOverlay).evaluate()) {
        expect((o.widget as RouteOverlay).route, isNull);
      }
      expect(fake.calls, 0);
      await unmount(tester);
    });

    // AC11 (intent 0014)
    testWidgets('router called only when the full-screen map opens',
        (tester) async {
      Finder cardMap(Event e) => find.byWidgetPredicate(
          (w) => w is RouteMap && identical(w.controls, e.controls));
      Future<void> open(Event e) async {
        await unmount(tester);
        await tester.pumpWidget(app(eventList()));
        await tester.pump();
        await tester.scrollUntilVisible(cardMap(e), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(fake.calls, 0, reason: 'the list made a call');
        await tester.tap(cardMap(e));
        await tester.pumpAndSettle();
        expect(find.byType(RouteMapPage), findsOneWidget);
      }

      // A feed route: no call.
      await open(events.firstWhere((e) => e.route != null));
      expect(fake.calls, 0);
      // No feed route: one call when the page opens, not again on reopen.
      final event = unrouted();
      await open(event);
      expect(fake.calls, 1);
      expect(approxLabel, findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(cardMap(event));
      await tester.pumpAndSettle();
      expect(fake.calls, 1);
      await unmount(tester);

      // Non-drawable geometry: no call, no label.
      await tester.pumpWidget(page(withControls(event, [
        control(0, 40.0, -75.2),
        control(1, 0, 0),
      ])));
      await tester.pump();
      expect(fake.calls, 1);
      expect(straightLabel, findsNothing);
      expect(approxLabel, findsNothing);
      await unmount(tester);
    });

    // AC12 (intent 0014)
    testWidgets('camera fitted to the controls does not jump on arrival',
        (tester) async {
      final pending = Completer<List<LatLong>?>();
      fake.answer = (c) => pending.future;
      final event = unrouted();
      await tester.pumpWidget(page(event));
      await tester.pump();
      final before = cameraOf(tester);
      final mapSize = tester.getSize(find.byType(FlutterMap));
      final geometry = RouteGeometry.fromLatLongs(usable(event));
      final fitted = RouteMap.fittedCamera(geometry, mapSize,
          padding: RouteMapPage.fitPadding(
              RideSummarySheet.initialExtent(mapSize.height)));
      expect(before.center, fitted.center);
      // A route reaching well outside the controls arrives later.
      final far = [
        ...usable(event),
        const LatLong(45, -70),
        const LatLong(35, -80),
      ];
      pending.complete(far);
      await tester.pumpAndSettle();
      expect(overlay(tester).route, far);
      final after = cameraOf(tester);
      expect(after.center, before.center);
      expect(after.zoom, before.zoom);
      // Every usable control is still in view.
      final rect = Offset.zero & mapSize;
      for (final c in usable(event)) {
        expect(rect.contains(after.latLngToScreenOffset(LatLng(c.lat, c.long))),
            isTrue);
      }
      await unmount(tester);
    });

    // AC14 (intent 0014)
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('labels themed, clear of attribution and handle ($mode)',
          (tester) async {
        final handle = tester.ensureSemantics();
        for (final answer in <Future<List<LatLong>?> Function(List<LatLong>)>[
          (c) async => FakeRouteService.wiggle(c),
          (c) async => null,
        ]) {
          RouteService.cache.clear();
          fake.answer = answer;
          await tester.pumpWidget(page(unrouted(), mode: mode));
          await tester.pump();
          final label = find.byType(RouteSourceLabel);
          expect(label, findsOneWidget);
          final scheme = Theme.of(tester.element(label)).colorScheme;
          final text = tester.widget<Text>(
              find.descendant(of: label, matching: find.byType(Text)));
          expect(text.style!.color, scheme.onSurfaceVariant);
          final box = tester.widget<DecoratedBox>(
              find.descendant(of: label, matching: find.byType(DecoratedBox)));
          expect((box.decoration as BoxDecoration).color, scheme.surface);
          final labelRect = tester.getRect(
              find.descendant(of: label, matching: find.byType(DecoratedBox)));
          final chip = tester.getRect(find.descendant(
              of: find.byType(MapAttributionChip),
              matching: find.byType(DecoratedBox)));
          final handleRect =
              tester.getRect(find.bySemanticsLabel(RegExp('ride summary')));
          expect(labelRect.overlaps(chip), isFalse);
          expect(labelRect.overlaps(handleRect), isFalse);
          expect(labelRect.overlaps(tester.getRect(sheetSurface)), isFalse);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await unmount(tester);
        }
        handle.dispose();
      });
    }

    // AC14 + AC15 (intent 0014): no hard-coded colours; the route code
    // touches no check-in, codes, ride state or reporting.
    test('route sources use theme roles and touch no rider data', () {
      for (final path in [
        'lib/route_map_page.dart',
        'lib/route_service.dart',
        'lib/route_polyline.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, isNot(contains('Colors.')), reason: path);
        expect(src, isNot(contains('Color(0x')), reason: path);
        for (final f in [
          'checkin.dart',
          'signature.dart',
          'report.dart',
          'activated_event.dart',
          'my_activated_events.dart',
          'location.dart',
          'app_settings.dart',
        ]) {
          expect(src, isNot(contains(f)), reason: '$path uses $f');
        }
      }
    });
  });
}
