// Event card route map with OSM tiles (intent 0010, slice b).
//
// Every map here uses a fake TileProvider (test/support/fake_tiles.dart);
// nothing touches the network.

import 'dart:async';
import 'dart:math' as math;

import 'package:ebrevet_card/control.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/route_sketch.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, unmount;
import 'support/fake_tiles.dart';
import 'support/fixtures.dart';

Control control(int i, double lat, double long) => Control.fromMap(i, {
      'dist_mi': i * 10,
      'lat': lat,
      'long': long,
      'name': 'C$i',
      'style': 'staffed',
      'open': '2026-06-01T09:00:00+00:00',
      'close': '2026-06-01T10:00:00+00:00',
    });

/// A loop: start and finish ~90 m apart.
final loopControls = [
  control(0, 40.0034216, -75.1976835),
  control(1, 40.37533, -75.0305),
  control(2, 40.9862789, -75.1439695),
  control(3, 40.0034934, -75.1966697),
];

/// Point to point, not a loop: start, two intermediates, finish.
final lineControls = [
  control(0, 40.0, -75.2),
  control(1, 40.4, -75.0),
  control(2, 40.7, -74.6),
  control(3, 41.0, -74.4),
];

Widget mapApp(List<Control> controls,
        {TileProvider? provider,
        double width = 400,
        ThemeMode mode = ThemeMode.light}) =>
    app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RouteMap(controls: controls, tileProvider: provider),
          ),
        ),
      ),
      mode: mode,
    );

MapCamera cameraOf(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(RouteOverlay)));

RouteSketchPainter overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byType(RouteOverlay), matching: find.byType(CustomPaint)))
    .painter! as RouteSketchPainter;

/// Inverse Web Mercator of tile corner (x, y) at zoom z.
LatLng tileCorner(int x, int y, int z) {
  final n = math.pow(2, z);
  final long = x / n * 360 - 180;
  final lat = math.atan(_sinh(math.pi * (1 - 2 * y / n))) * 180 / math.pi;
  return LatLng(lat, long);
}

double _sinh(num x) => (math.exp(x) - math.exp(-x)) / 2;

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
    RouteMap.tileProviderFactory = RouteMap.defaultTileProvider;
  });

  // AC2 (intent 0010)
  testWidgets('static map: fixed aspect ratio, no interaction', (tester) async {
    final controls = events.first.controls;
    for (final width in [400.0, 300.0]) {
      await tester.pumpWidget(
          mapApp(controls, provider: FakeTileProvider(), width: width));
      final size = tester.getSize(find.byType(RouteMap));
      expect(size.width, width);
      expect(size.height, closeTo(width / RouteSketch.aspectRatio, 0.01));
    }
    expect(RouteMap.aspectRatio, RouteSketch.aspectRatio);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.interactionOptions.flags, InteractiveFlag.none);
    expect(
        find.ancestor(
            of: find.byType(FlutterMap), matching: find.byType(IgnorePointer)),
        findsWidgets);
    await unmount(tester);
  });

  // AC2 (intent 0010)
  testWidgets('camera fits the padded route bounds; every control in view',
      (tester) async {
    for (final controls in [
      events.first.controls,
      loopControls,
      lineControls,
      events.last.controls
    ]) {
      // Fresh map each time; checked on its very first frame, before
      // flutter_map's post-frame initialCameraFit.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(mapApp(controls, provider: FakeTileProvider()));
      final camera = cameraOf(tester);
      final geometry = RouteMap(controls: controls).geometry;
      for (final p in geometry.latLongs) {
        expect(camera.visibleBounds.contains(LatLng(p.lat, p.long)), isTrue,
            reason: 'control $p outside the map view');
      }
      // Same Web Mercator projection as route_geometry.dart: the camera puts
      // each control where RouteGeometry.fit puts it in the same box.
      final size = tester.getSize(find.byType(RouteMap));
      final fitted = geometry.fit(size.width, size.height);
      for (var i = 0; i < fitted.length; i++) {
        final onMap = camera.latLngToScreenOffset(
            LatLng(geometry.latLongs[i].lat, geometry.latLongs[i].long));
        expect(onMap.dx, closeTo(fitted[i].x, 0.5));
        expect(onMap.dy, closeTo(fitted[i].y, 0.5));
      }
      // The padded box corners round-trip through the inverse projection.
      final sw = RouteGeometry.project(geometry.paddedSouthWest);
      expect(sw.x, closeTo(geometry.paddedBounds.minX, 1e-6));
      expect(sw.y, closeTo(geometry.paddedBounds.maxY, 1e-6));
      // After the post-frame fit the camera has not moved.
      await tester.pump();
      expect(cameraOf(tester).center, camera.center);
      expect(cameraOf(tester).zoom, closeTo(camera.zoom, 1e-9));
    }
    await unmount(tester);
  });

  // AC2 (intent 0010)
  testWidgets('camera refits when the controls or the width change',
      (tester) async {
    Future<void> expectAllInView(List<Control> controls) async {
      await tester.pump();
      final camera = cameraOf(tester);
      for (final p in RouteMap(controls: controls).geometry.latLongs) {
        expect(camera.visibleBounds.contains(LatLng(p.lat, p.long)), isTrue,
            reason: 'control $p outside the map view');
      }
    }

    final provider = FakeTileProvider();
    await tester.pumpWidget(mapApp(lineControls, provider: provider));
    await expectAllInView(lineControls);
    await tester.pumpWidget(mapApp(events.first.controls, provider: provider));
    await expectAllInView(events.first.controls);
    await tester.pumpWidget(
        mapApp(events.first.controls, provider: provider, width: 250));
    await expectAllInView(events.first.controls);
    await unmount(tester);
  });

  // AC3 (intent 0010)
  testWidgets('OSM tile constants, attribution, only visible tiles',
      (tester) async {
    expect(RouteMap.tileUrlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(RouteMap.userAgentPackageName, isNotEmpty);
    final fake = FakeTileProvider();
    await tester.pumpWidget(mapApp(events.first.controls, provider: fake));
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, RouteMap.tileUrlTemplate);
    expect(layer.tileProvider.headers['User-Agent'],
        'flutter_map (${RouteMap.userAgentPackageName})');
    expect(layer.panBuffer, 0);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RouteMap),
            matching: find.text(RouteMap.attribution)),
        findsOneWidget);

    // No prefetching: every requested tile overlaps the visible bounds.
    final view = cameraOf(tester).visibleBounds;
    expect(fake.requested, isNotEmpty);
    for (final c in fake.requested) {
      final tile = LatLngBounds(
          tileCorner(c.x, c.y + 1, c.z), tileCorner(c.x + 1, c.y, c.z));
      expect(tile.isOverlapping(view), isTrue, reason: 'tile $c not in view');
    }
    await unmount(tester);
  });

  // AC4 (intent 0010)
  testWidgets('overlay reuses the slice (a) painter with theme colors',
      (tester) async {
    await tester.pumpWidget(mapApp(lineControls, provider: FakeTileProvider()));
    final scheme = Theme.of(tester.element(find.byType(RouteMap))).colorScheme;
    final p = overlayPainter(tester);
    expect(p.line, scheme.primary);
    expect(p.casing, scheme.surface);
    expect(p.start, scheme.tertiary);
    expect(p.finish, scheme.onSurface);
    expect(p.intermediate, scheme.onSurfaceVariant);
    expect(p.line, isNot(p.casing));
    expect(p.start, isNot(p.finish));
    // Points in control order, projected by the map camera.
    expect(p.screenPoints, hasLength(p.geometry.points.length));
    final n = p.geometry.points.length;
    expect(p.markers.first, SketchMarker.start);
    expect(p.markers.last, SketchMarker.finish);
    expect(
        p.markers.sublist(1, n - 1), everyElement(SketchMarker.intermediate));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(mapApp(loopControls, provider: FakeTileProvider()));
    expect(overlayPainter(tester).markers, [
      SketchMarker.startFinish,
      SketchMarker.intermediate,
      SketchMarker.intermediate,
      null,
    ]);
    await unmount(tester);
  });

  // AC5 (intent 0010)
  testWidgets('tile provider is injectable; the fake one is used',
      (tester) async {
    final fake = FakeTileProvider();
    await tester.pumpWidget(mapApp(events.first.controls, provider: fake));
    expect(
        identical(tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
            fake),
        isTrue);
    expect(fake.requested, isNotEmpty);

    // The single seam, used when no provider is passed.
    final seam = FakeTileProvider();
    RouteMap.tileProviderFactory = () => seam;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(mapApp(events.first.controls));
    expect(
        identical(tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
            seam),
        isTrue);
    await unmount(tester);
  });

  // AC5 (intent 0010)
  test('under flutter test the default provider makes no requests', () {
    expect(RouteMap.isFlutterTest, isTrue);
    expect(RouteMap.defaultTileProvider(), isA<NoTileProvider>());
    expect(RouteMap.defaultTileProvider(), isNot(isA<NetworkTileProvider>()));
  });

  // AC6 (intent 0010)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('tiles fail: route, background and attribution remain ($mode)',
        (tester) async {
      final failing = FakeTileProvider(fail: true);
      await tester.pumpWidget(
          mapApp(events.first.controls, provider: failing, mode: mode));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(failing.requested, isNotEmpty);
      final scheme =
          Theme.of(tester.element(find.byType(RouteMap))).colorScheme;
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.backgroundColor, scheme.surfaceContainerHighest);
      // No error tile image: a failed tile stays empty.
      expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).errorImage, isNull);
      expect(
          find.descendant(
              of: find.byType(TileLayer), matching: find.byType(Image)),
          findsNothing);
      expect(overlayPainter(tester).screenPoints, isNotEmpty);
      expect(find.text(RouteMap.attribution), findsOneWidget);
      await unmount(tester);
      expect(tester.takeException(), isNull);
    });
  }

  // AC6 (intent 0010): tiles disabled.
  testWidgets('tiles disabled: route and attribution still drawn',
      (tester) async {
    await tester
        .pumpWidget(mapApp(events.first.controls, provider: NoTileProvider()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(overlayPainter(tester).screenPoints, isNotEmpty);
    expect(find.text(RouteMap.attribution), findsOneWidget);
    await unmount(tester);
  });

  // AC7 (intent 0010)
  testWidgets('map semantics label counts the event controls', (tester) async {
    final handle = tester.ensureSemantics();
    final controls = [...events.first.controls, control(99, 0, 0)];
    await tester.pumpWidget(mapApp(controls, provider: FakeTileProvider()));
    expect(
        find.bySemanticsLabel(
            'Map of the route area with ${controls.length} controls'),
        findsOneWidget);
    handle.dispose();
    await unmount(tester);
  });

  // AC7 (intent 0010)
  testWidgets('not drawable: slice (a) placeholder, no map, no tile layer',
      (tester) async {
    final handle = tester.ensureSemantics();
    for (final controls in [
      [control(0, 40.0, -75.2)],
      [control(0, 0, 0), control(1, 0, 0)],
      [control(0, double.nan, -75.2), control(1, 40.0, 200)],
      [control(0, 40.0, -75.2), control(1, 40.0, -75.2)],
    ]) {
      final fake = FakeTileProvider();
      await tester.pumpWidget(mapApp(controls, provider: fake));
      final media = find.byType(RouteMap);
      expect(tester.getSize(media),
          const Size(400, 400 / RouteSketch.aspectRatio));
      expect(find.descendant(of: media, matching: find.byType(RouteSketch)),
          findsOneWidget);
      expect(find.byIcon(Icons.route), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byType(TileLayer), findsNothing);
      expect(fake.requested, isEmpty);
      expect(
          find.bySemanticsLabel(
              'Sketch of the route with ${controls.length} controls'),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Map of the route')), findsNothing);
    }
    handle.dispose();
    await unmount(tester);
  });

  // AC7 (intent 0010): map -> placeholder -> map gets a fresh tile provider
  // (the old one was disposed with its TileLayer).
  testWidgets('placeholder and back: new map, new tile provider',
      (tester) async {
    final made = <FakeTileProvider>[];
    RouteMap.tileProviderFactory = () {
      final p = FakeTileProvider();
      made.add(p);
      return p;
    };
    await tester.pumpWidget(mapApp(lineControls));
    await tester.pumpWidget(mapApp([control(0, 40.0, -75.2)]));
    expect(find.byType(TileLayer), findsNothing);
    await tester.pumpWidget(mapApp(lineControls));
    expect(made, hasLength(2));
    expect(
        identical(tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
            made.last),
        isTrue);
    expect(made.last.requested, isNotEmpty);
    await unmount(tester);
  });

  // AC9 (intent 0010)
  testWidgets('lazy list: an off-screen card has no map until scrolled to',
      (tester) async {
    final fake = FakeTileProvider();
    RouteMap.tileProviderFactory = () => fake;
    final list = [...events, ...events]; // long enough to scroll
    await tester.pumpWidget(app(Scaffold(
        body: ListView(children: [for (final e in list) EventCard(e)]))));
    await tester.pump();
    final built = find.byType(FlutterMap, skipOffstage: false);
    expect(built.evaluate().length, lessThan(list.length));
    final last = find.byWidgetPredicate(
        (w) => w is EventCard && identical(w.event, list.last),
        skipOffstage: false);
    expect(last, findsNothing);

    await tester.scrollUntilVisible(last, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(last, findsOneWidget);
    expect(find.descendant(of: last, matching: find.byType(FlutterMap)),
        findsOneWidget);
    // Cards scrolled away are disposed: the list stays lazy.
    expect(built.evaluate().length, lessThan(list.length));
    await unmount(tester);
  });

  // AC9 (intent 0010)
  test('network tiles: memory image cache only, same key on reopen', () {
    final a = RouteMap.networkTileProvider() as NetworkTileProvider;
    final b = RouteMap.networkTileProvider() as NetworkTileProvider;
    expect(a.cachingProvider, isA<DisabledMapCachingProvider>());
    final layer = TileLayer(urlTemplate: RouteMap.tileUrlTemplate);
    const c = TileCoordinates(1, 2, 3);
    // Flutter's image cache is keyed by the image provider, which is keyed
    // by tile URL, so a new map (list reopened) reuses fetched tiles.
    final never = Completer<void>().future;
    expect(a.getImageWithCancelLoadingSupport(c, layer, never),
        b.getImageWithCancelLoadingSupport(c, layer, never));
    a.dispose();
    b.dispose();
    layer.tileProvider.dispose();
  });
}
