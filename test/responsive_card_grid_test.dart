// Responsive event card grid on tablets and desktop (intent 0012).
//
// Layout tests with small fake cards of uneven height, plus real
// EventCards from the mock feed and My Rides. No network: the mock feed is
// read from disk and every route map uses a fake tile provider.

import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/app_tokens.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_activated_events.dart';
import 'package:ebrevet_card/my_activated_events_page.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/responsive_card_grid.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, eventList, unmount;
import 'support/fake_tiles.dart';
import 'support/fixtures.dart';
import 'support/grid.dart';

const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// A stand-in card whose height depends on [index], so rows are uneven.
class FakeCard extends StatelessWidget {
  final int index;
  const FakeCard(this.index, {super.key});

  double get height => 80.0 + 45 * (index % 4);

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: Card(child: Text('Card $index')));
}

/// The grid inside the same page margins as the real pages.
Widget page({Widget? header, required List<Widget> cards}) => Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ResponsiveCardGrid(header: header, cards: cards),
      ),
    );

Widget fakeGrid(int n, {bool header = true}) => app(page(
      header: header ? const Text('Header') : null,
      cards: [for (var i = 0; i < n; i++) FakeCard(i)],
    ));

final fakeCards = find.byType(FakeCard);

/// Window width -> cards per row (AC3; 1920 means at least 3).
final expectedColumns = <double, int>{390.0: 1, 744.0: 2, 1280.0: 3, 1920.0: 3};

/// Copy of [e] with a new ID and, optionally, a gravel note.
Event copyOf(Event e, int i, {bool gravel = false}) =>
    Event.fromJson(Map<String, dynamic>.from(e.toJson))
      ..eventID = '${e.eventID}-grid-$i'
      ..gravelDistance = gravel ? (e.distance ~/ 3) : 0;

/// Groups [rects] into rows by top offset, in order.
List<List<Rect>> rowsOf(List<Rect> rects) {
  final sorted = [...rects]..sort((a, b) {
      final t = a.top.compareTo(b.top);
      return t != 0 ? t : a.left.compareTo(b.left);
    });
  final rows = <List<Rect>>[];
  for (final r in sorted) {
    if (rows.isNotEmpty && (rows.last.first.top - r.top).abs() < 0.5) {
      rows.last.add(r);
    } else {
      rows.add([r]);
    }
  }
  return rows;
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
    RouteMap.tileProviderFactory = () => FakeTileProvider();
  });

  tearDown(() {
    ScheduledEvents.events = <Event>[];
    MockServer.now = DateTime.now;
    RouteMap.tileProviderFactory = RouteMap.defaultTileProvider;
  });

  // AC2 (intent 0012)
  group('columnsFor', () {
    test('counts from the maximum card width and the available width', () {
      expect(ResponsiveCardGrid.columnsFor(390), 1);
      expect(ResponsiveCardGrid.columnsFor(599), 1);
      expect(ResponsiveCardGrid.columnsFor(744), 2);
      expect(ResponsiveCardGrid.columnsFor(839), 2);
      expect(ResponsiveCardGrid.columnsFor(1280), 3);
      for (final w in [1920.0, 2560.0, 3840.0]) {
        expect(ResponsiveCardGrid.columnsFor(w), greaterThanOrEqualTo(3));
      }
    });

    test('never lets a card exceed maxCardWidth', () {
      const gutter = 16.0;
      for (var w = 100.0; w <= 4000; w += 7) {
        final n = ResponsiveCardGrid.columnsFor(w, gutter: gutter);
        expect(n, greaterThanOrEqualTo(1));
        expect((w - (n - 1) * gutter) / n,
            lessThanOrEqualTo(ResponsiveCardGrid.maxCardWidth + 1e-9),
            reason: 'width $w');
      }
    });

    test('M3 window size classes are documented in the code', () {
      final src = File('lib/responsive_card_grid.dart').readAsStringSync();
      for (final c in [
        'compact',
        'medium',
        'expanded',
        'large',
        'extra-large',
        '600',
        '839',
        '840',
        '1199',
        '1200',
        '1599',
        '1600',
      ]) {
        expect(src, contains(c));
      }
    });
  });

  // AC3 (intent 0012): cards per row by window width.
  expectedColumns.forEach((width, columns) {
    testWidgets('$width dp wide gives $columns card(s) per row',
        (tester) async {
      setSurface(tester, width);
      await tester.pumpWidget(fakeGrid(12));
      final perRow = cardsPerRow(tester, fakeCards);
      if (width >= 1920) {
        expect(perRow, greaterThanOrEqualTo(columns));
      } else {
        expect(perRow, columns);
      }
    });
  });

  // AC4 (intent 0012)
  for (final width in [1920.0, 3840.0]) {
    testWidgets('centred body capped at maxBodyWidth at $width dp',
        (tester) async {
      setSurface(tester, width);
      await tester.pumpWidget(fakeGrid(12));
      final rects = rectsOf(tester, fakeCards);
      final area = rects.reduce((a, b) => a.expandToInclude(b));
      expect(area.width, lessThanOrEqualTo(ResponsiveCardGrid.maxBodyWidth));
      // Centred: equal space left and right.
      expect(area.left, moreOrLessEquals(width - area.right, epsilon: 0.5));
      if (width == 3840) {
        expect(area.left, greaterThan(16), reason: 'not edge to edge');
      }
      for (final r in rects) {
        expect(r.width, lessThanOrEqualTo(ResponsiveCardGrid.maxCardWidth));
      }
    });
  }

  // AC5 (intent 0012): spaceMedium gutters both ways, page margins as today.
  for (final width in [390.0, 744.0, 1280.0]) {
    testWidgets('spaceMedium between cards in both directions at $width dp',
        (tester) async {
      setSurface(tester, width, 2000);
      await tester.pumpWidget(fakeGrid(9, header: false));
      final gap = AppTokens.of(tester.element(fakeCards.first)).spaceMedium;
      expect(gap, 16);
      final rows = rowsOf(rectsOf(tester, fakeCards));
      expect(rows.length, greaterThan(1));
      // Page margin as today.
      expect(rows.first.first.left, 16);
      expect(rows.first.first.top, 16);
      for (var r = 0; r < rows.length; r++) {
        for (var i = 1; i < rows[r].length; i++) {
          expect(rows[r][i].left - rows[r][i - 1].right,
              moreOrLessEquals(gap, epsilon: 0.01));
        }
        if (r > 0) {
          final prevBottom =
              rows[r - 1].map((x) => x.bottom).reduce((a, b) => a > b ? a : b);
          expect(rows[r].first.top - prevBottom,
              moreOrLessEquals(gap, epsilon: 0.01));
        }
      }
    });
  }

  // AC6 (intent 0012): uneven heights, top-aligned, no overlap or clipping.
  for (final width in [744.0, 1280.0]) {
    testWidgets('uneven real cards at $width dp: top-aligned, no overlap',
        (tester) async {
      setSurface(tester, width, 3000);
      final cards = [
        for (var i = 0; i < 6; i++)
          EventCard(
            copyOf(events[i % events.length], i, gravel: i.isEven),
            // My Rides delete button on some cards.
            hasDelete: i % 3 == 0,
            showRouteMap: i % 3 != 2,
          ),
      ];
      await tester.pumpWidget(app(page(header: const Text('H'), cards: cards)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final cardFinder = find.byType(EventCard);
      expect(cardFinder, findsNWidgets(6));
      expect(find.byIcon(Icons.delete), findsWidgets);
      expect(find.textContaining('Gravel:'), findsWidgets);
      final rects = rectsOf(tester, cardFinder);
      expectNoOverlap(rects);
      final rows = rowsOf(rects);
      final columns = width == 744 ? 2 : 3;
      expect(rows.length, (6 / columns).ceil());
      for (final row in rows) {
        expect(row.length, columns);
      }
      // Heights differ, so this really is the uneven case.
      expect(rects.map((r) => r.height).toSet().length, greaterThan(1));
      // No clipping: each card is as tall as its content column.
      for (final e in cardFinder.evaluate()) {
        final card = find.byWidget(e.widget);
        final content =
            find.descendant(of: card, matching: find.byType(Column)).first;
        expect(tester.getSize(content).height,
            lessThanOrEqualTo(tester.getSize(card).height + 0.01));
      }
      await unmount(tester);
    });
  }

  // AC9 (intent 0012): live reflow on resize and rotation.
  testWidgets('resizing and rotating reflows the columns', (tester) async {
    setSurface(tester, 390);
    await tester.pumpWidget(fakeGrid(12));
    expect(cardsPerRow(tester, fakeCards), 1);
    final steps = <Size, int>{
      const Size(744, 900): 2,
      const Size(1280, 900): 3,
      // Landscape tablet, then the same tablet in portrait.
      const Size(1024, 744): 2,
      const Size(744, 1024): 2,
      // Landscape phone, then portrait.
      const Size(844, 390): 2,
      const Size(390, 844): 1,
    };
    for (final size in steps.keys) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(cardsPerRow(tester, fakeCards), steps[size], reason: '$size');
    }
  });

  // AC9 (intent 0012): the same with the real event list.
  testWidgets('event list reflows 390 -> 744 -> 1280 dp', (tester) async {
    setSurface(tester, 390, 3000);
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    final cards = find.byType(EventCard);
    expect(cardsPerRow(tester, cards), 1);
    expect(tester.takeException(), isNull, reason: 'at 390');
    tester.view.physicalSize = const Size(744, 3000);
    await tester.pump();
    expect(cardsPerRow(tester, cards), 2);
    expect(tester.takeException(), isNull, reason: 'at 744');
    tester.view.physicalSize = const Size(1280, 3000);
    await tester.pump();
    expect(cardsPerRow(tester, cards), 3);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  // AC1 (intent 0012): one shared widget for both lists. No new dependency
  // is checked by the pubspec test in event_list_screen_test.dart.
  testWidgets('event list uses ResponsiveCardGrid', (tester) async {
    await tester.pumpWidget(app(eventList()));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byType(LatestEventList),
            matching: find.byType(ResponsiveCardGrid)),
        findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    await unmount(tester);
  });

  group('My Rides', () {
    late Directory docs;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('ebrevet_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              pathProviderChannel, (call) async => docs.path);
    });

    tearDown(() {
      for (final a in [...MyActivatedEvents.myActivatedEventsList]) {
        MyActivatedEvents.deleteMyActivatedEvent(a);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      try {
        docs.deleteSync(recursive: true);
      } catch (_) {}
    });

    // AC1 + AC8 (intent 0012): empty list renders without error.
    testWidgets('empty My Rides renders with the grid', (tester) async {
      expect(MyActivatedEvents.myActivatedEventsList, isEmpty);
      await tester.pumpWidget(app(const MyActivatedEventsPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ResponsiveCardGrid), findsOneWidget);
      expect(find.byType(EventCard), findsNothing);
    });

    // AC8 (intent 0012)
    testWidgets('same column counts; sketch, delete and tap unchanged',
        (tester) async {
      await AppSettings.canDeletePastEvents.setValue(true);
      for (var i = 0; i < 6; i++) {
        final ride = MyActivatedEvents.addActivate(events[i],
            riderID: '12345', startStyle: StartStyle.preRide);
        // Finished: the widest outcome row ("FINISH No Finish" plus
        // CERTIFICATE), which used to overflow a phone-width card.
        ride.outcomes.overallOutcome = OverallOutcome.finish;
      }
      for (final width in const [390.0, 744.0, 1280.0]) {
        setSurface(tester, width, 3000);
        await tester.pumpWidget(app(const MyActivatedEventsPage()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final cards = find.byType(EventCard);
        expect(cardsPerRow(tester, cards), expectedColumns[width],
            reason: '$width dp');
        for (final card in tester.widgetList<EventCard>(cards)) {
          expect(card.showRouteMap, isFalse);
          expect(card.hasDelete, isTrue);
        }
        expect(find.byType(RouteMap), findsNothing);
      }
      // Delete still removes the ride and the grid reflows.
      final before = find.byType(EventCard).evaluate().length;
      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();
      expect(find.text('Please Confirm'), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.byType(EventCard), findsNWidgets(before - 1));
      expect(MyActivatedEvents.myActivatedEventsList.length, 5);
      expect(tester.takeException(), isNull);
      await AppSettings.canDeletePastEvents.setValue(false);
      await unmount(tester);
    });
  });
}
