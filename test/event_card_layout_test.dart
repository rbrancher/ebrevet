// Event card hierarchy and route sketch (intent 0009, slice a).
//
// Uses the mock feed (assets/mock/future_events.json) through MockServer;
// nothing here touches the network.

import 'dart:io';

import 'package:ebrevet_card/control.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_activated_events.dart';
import 'package:ebrevet_card/my_activated_events_page.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/route_sketch.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, eventList, unmount, labelOf;
import 'support/fixtures.dart';

const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Control control(int i, double lat, double long) => Control.fromMap(i, {
      'dist_mi': i * 10,
      'lat': lat,
      'long': long,
      'name': 'C$i',
      'style': 'staffed',
      'open': '2026-06-01T09:00:00+00:00',
      'close': '2026-06-01T10:00:00+00:00',
    });

Widget sketchApp(List<Control> controls, {double width = 400}) => app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RouteSketch(controls: controls),
          ),
        ),
      ),
    );

TextStyle styleOf(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).text.style!;

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
  });

  group('RouteSketch', () {
    // AC3 (intent 0009)
    testWidgets('fixed aspect ratio, CustomPaint, no gestures or scrolling',
        (tester) async {
      final controls = events.first.controls;
      for (final width in [400.0, 300.0]) {
        await tester.pumpWidget(sketchApp(controls, width: width));
        final size = tester.getSize(find.byType(RouteSketch));
        expect(size.width, width);
        expect(size.height, closeTo(width / RouteSketch.aspectRatio, 0.01));
      }
      final sketch = find.byType(RouteSketch);
      final painter = find.descendant(
          of: sketch,
          matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is RouteSketchPainter));
      expect(painter, findsOneWidget);
      expect(
          find.descendant(of: sketch, matching: find.byType(GestureDetector)),
          findsNothing);
      expect(find.descendant(of: sketch, matching: find.byType(InkWell)),
          findsNothing);
      expect(find.descendant(of: sketch, matching: find.byType(Scrollable)),
          findsNothing);
      expect(find.descendant(of: sketch, matching: find.byType(Listener)),
          findsNothing);
      // No render object under the sketch handles pointers.
      final renders = find
          .descendant(of: sketch, matching: find.byWidgetPredicate((_) => true))
          .evaluate()
          .map((e) => e.renderObject);
      expect(
          renders.any((r) =>
              r is RenderPointerListener || r is RenderSemanticsGestureHandler),
          isFalse);
    });

    // AC3 (intent 0009)
    testWidgets('colors come from the ColorScheme', (tester) async {
      await tester.pumpWidget(sketchApp(events.first.controls));
      final scheme =
          Theme.of(tester.element(find.byType(RouteSketch))).colorScheme;
      final p = tester
          .widget<CustomPaint>(find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is RouteSketchPainter))
          .painter! as RouteSketchPainter;
      expect(p.line, scheme.primary);
      expect(p.casing, scheme.surface);
      expect(p.line, isNot(p.casing));
      expect(p.start, isNot(p.finish));
      final bg = tester.widget<ColoredBox>(find.descendant(
          of: find.byType(RouteSketch), matching: find.byType(ColoredBox)));
      expect(bg.color, scheme.surfaceContainerHighest);
    });

    // AC3 (intent 0009)
    test('markers: start, intermediates and finish in control order', () {
      final p = RouteSketchPainter(
        geometry: RouteSketch(controls: [
          control(0, 40.0, -75.2),
          control(1, 40.4, -75.0),
          control(2, 41.0, -75.1),
        ]).geometry,
        line: const Color(0xFF000001),
        casing: const Color(0xFF000002),
        start: const Color(0xFF000003),
        finish: const Color(0xFF000004),
        intermediate: const Color(0xFF000005),
      );
      expect(p.markers, [
        SketchMarker.start,
        SketchMarker.intermediate,
        SketchMarker.finish,
      ]);
    });

    // AC3 (intent 0009)
    test('a loop gets one combined start/finish marker', () {
      final p = RouteSketchPainter(
        geometry: RouteSketch(controls: [
          control(0, 40.0034216, -75.1976835),
          control(1, 40.37533, -75.0305),
          control(2, 40.9862789, -75.1439695),
          control(3, 40.0034934, -75.1966697), // ~90 m from the start
        ]).geometry,
        line: const Color(0xFF000001),
        casing: const Color(0xFF000002),
        start: const Color(0xFF000003),
        finish: const Color(0xFF000004),
        intermediate: const Color(0xFF000005),
      );
      expect(p.markers, [
        SketchMarker.startFinish,
        SketchMarker.intermediate,
        SketchMarker.intermediate,
        null,
      ]);
      expect(p.markers, isNot(contains(SketchMarker.start)));
      expect(p.markers, isNot(contains(SketchMarker.finish)));
    });

    // AC4 (intent 0009)
    testWidgets('semantics label counts the event controls', (tester) async {
      final handle = tester.ensureSemantics();
      final e = events.first;
      // One invalid control: the label still uses the event's count.
      final controls = [...e.controls, control(99, 0, 0)];
      await tester.pumpWidget(sketchApp(controls));
      expect(
          find.bySemanticsLabel(
              'Sketch of the route with ${controls.length} controls'),
          findsOneWidget);
      handle.dispose();
    });

    // AC4 (intent 0009)
    testWidgets('not drawable: same-size placeholder with icon, no painter',
        (tester) async {
      final handle = tester.ensureSemantics();
      for (final controls in [
        [control(0, 40.0, -75.2)],
        [control(0, 0, 0), control(1, 0, 0)],
        [control(0, 40.0, -75.2), control(1, 40.0, -75.2)],
      ]) {
        await tester.pumpWidget(sketchApp(controls));
        final sketch = find.byType(RouteSketch);
        expect(tester.getSize(sketch),
            const Size(400, 400 / RouteSketch.aspectRatio));
        expect(find.descendant(of: sketch, matching: find.byIcon(Icons.route)),
            findsOneWidget);
        expect(
            find.descendant(
                of: sketch,
                matching: find.byWidgetPredicate((w) =>
                    w is CustomPaint && w.painter is RouteSketchPainter)),
            findsNothing);
        expect(
            find.bySemanticsLabel(
                'Sketch of the route with ${controls.length} controls'),
            findsOneWidget);
      }
      handle.dispose();
    });
  });

  group('EventCard', () {
    // AC5 (intent 0009)
    testWidgets('each card in the event list has one sketch, at the top',
        (tester) async {
      await tester.pumpWidget(app(eventList()));
      await tester.pump();
      final cards = find.byType(EventCard, skipOffstage: false);
      expect(cards, findsWidgets);
      for (final card in cards.evaluate()) {
        final cardFinder = find.byWidget(card.widget, skipOffstage: false);
        final sketch = find.descendant(
            of: cardFinder,
            matching: find.byType(RouteSketch, skipOffstage: false),
            skipOffstage: false);
        expect(sketch, findsOneWidget);
        final ev = (card.widget as EventCard).event;
        expect(tester.widget<RouteSketch>(sketch).controls, ev.controls);
        final title = find.descendant(
            of: cardFinder,
            matching: find.text(ev.nameDist, skipOffstage: false),
            skipOffstage: false);
        // Media first: the sketch is above the text.
        expect(tester.getRect(sketch).bottom,
            lessThanOrEqualTo(tester.getRect(title).top));
        expect(tester.getRect(sketch).top,
            closeTo(tester.getRect(cardFinder).top, 8));
      }
      await unmount(tester);
    });

    // AC6 (intent 0009)
    testWidgets('headline is titleLarge and bolder than the club subhead',
        (tester) async {
      await tester.pumpWidget(app(eventList()));
      await tester.pump();
      final theme = Theme.of(tester.element(find.byType(LatestEventList)));
      final ev = tester.widget<EventCard>(find.byType(EventCard).first).event;
      final head = styleOf(tester, find.text(ev.nameDist).first);
      final club = Region(regionID: ev.regionID).clubName;
      final sub = styleOf(tester, find.text(club).first);
      expect(head.fontSize, theme.textTheme.titleLarge!.fontSize);
      expect(head.fontWeight!.value,
          greaterThan(theme.textTheme.titleMedium!.fontWeight!.value));
      expect(head.fontSize, greaterThan(sub.fontSize!));
      expect(head.fontWeight!.value, greaterThan(sub.fontWeight!.value));
      expect(sub.color, theme.colorScheme.onSurfaceVariant);
      await unmount(tester);
    });

    // AC7 + AC8 (intent 0009): every item is still on the card. Distance and
    // gravel stay as full text (no chips), so screen readers get all of it.
    testWidgets('card keeps every item it showed before', (tester) async {
      final e = events.first..gravelDistance = 30;
      final now = DateTime.now();
      final upcoming = events.firstWhere((x) =>
          x.startTimeWindow.onTime != null &&
          !x.isUnderway &&
          x.startTimeWindow.onTime!.isAfter(now));
      for (final ev in {e, upcoming}) {
        await tester.pumpWidget(
            app(Scaffold(body: ListView(children: [EventCard(ev)]))));
        final card = find.byType(EventCard);
        Finder inCard(Finder f) => find.descendant(of: card, matching: f);
        final club = Region(regionID: ev.regionID).clubName;
        expect(inCard(find.text(ev.nameDist)), findsOneWidget);
        expect(inCard(find.text(club)), findsOneWidget);
        expect(inCard(find.text('${ev.startCity}, ${ev.startState}')),
            findsOneWidget);
        expect(inCard(find.text(ev.startTimeWindow.startStyle.description)),
            findsOneWidget);
        if (ev.gravelDistance > 0) {
          expect(
              inCard(find.text(
                  'Gravel: ${ev.gravelDistance}K of ${ev.distance}K'
                  ' (${(100.0 * ev.gravelDistance / ev.distance).round()}%) unpaved')),
              findsOneWidget);
        }
        if (ev.startTimeWindow.onTime != null) {
          if (ev.isUnderway) {
            expect(inCard(find.text('UNDERWAY!')), findsOneWidget);
          } else {
            expect(inCard(find.text('${ev.dateTime} (${ev.eventStatusText})')),
                findsOneWidget);
          }
        }
        expect(inCard(find.text('Latest Cue Ver: ${ev.cueVersionString}')),
            findsOneWidget);
        expect(inCard(find.byIcon(Icons.info_outline)), findsOneWidget);
        expect(inCard(find.byIcon(Icons.checklist_rtl)), findsOneWidget);
        // Outcome row (intent 0002): DNS description for a never-ridden event.
        expect(
            inCard(find.text(OverallOutcome.dns.description)), findsOneWidget);
        final filled = tester
            .widgetList<FilledButton>(
                inCard(find.byWidgetPredicate((w) => w is FilledButton)))
            .toList();
        expect(filled.length, lessThanOrEqualTo(1));
        if (identical(ev, upcoming) && filled.isNotEmpty) {
          expect({'RIDE', 'PRE-RIDE'}, contains(labelOf(filled.single)));
        }
      }
      await unmount(tester);
    });

    // AC9 (intent 0009)
    testWidgets('My Rides card renders with the shared widget', (tester) async {
      final docs = Directory.systemTemp.createTempSync('ebrevet_test_');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          pathProviderChannel, (call) async => docs.path);
      final ev = events.first;
      final ride = MyActivatedEvents.addActivate(ev,
          riderID: '12345', startStyle: StartStyle.preRide);
      ride.outcomes.overallOutcome = OverallOutcome.finish;
      try {
        await tester.pumpWidget(app(const MyActivatedEventsPage()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final card = find.byType(EventCard);
        expect(card, findsOneWidget);
        expect(find.descendant(of: card, matching: find.text(ev.nameDist)),
            findsOneWidget);
        expect(find.descendant(of: card, matching: find.byType(RouteSketch)),
            findsOneWidget);
        expect(find.text('CERTIFICATE'), findsOneWidget);
      } finally {
        MyActivatedEvents.deleteMyActivatedEvent(ride);
        await unmount(tester);
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
        try {
          docs.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
