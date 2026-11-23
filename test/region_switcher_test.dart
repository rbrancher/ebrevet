// Intent 0017: segmented region switcher on the events page.
//
// Mock shared preferences, a temp documents directory and the mock server
// (support/event_sources.dart). Pumps LatestEventList, the body of
// ScheduledEventsPage under its app bar (the page itself runs a location
// permission check). Never the network.

import 'dart:io';

import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/event_sources.dart';

final a = regionSource('938017'); // PA: Eastern
final b = regionSource(MockServer.altRegionID); // CA: San Francisco
final unknown = regionSource('999999');

final switcher = find.byKey(const Key('region-switcher'));

Finder segment(String label) =>
    find.descendant(of: switcher, matching: find.text(label));

/// A 390 dp wide phone.
void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(tester.view.reset);
}

Widget app(SourceSelection selection) {
  final dn = DayNight();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: dn),
      ChangeNotifierProvider(create: (_) => ControlState()),
      ChangeNotifierProvider.value(value: selection),
    ],
    child: MaterialApp(
      scaffoldMessengerKey: AppSnack.messengerKey,
      theme: dn.dayTheme,
      home: Scaffold(
        appBar: AppBar(title: const Text('Events')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: LatestEventList(eventFilter: EventFilter.all),
        ),
      ),
    ),
  );
}

/// Unmount so LatestEventList cancels its refresh timer.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5)); // snack timers
}

List<String> ids(ScheduledEventsSource s) =>
    [for (final e in ScheduledEvents.cacheFor(s).events) e.eventID];

List<String> shownIDs(WidgetTester tester) => [
      for (final c in tester
          .widgetList<EventCard>(find.byType(EventCard, skipOffstage: false)))
        c.event.eventID
    ];

/// The grid builds cards lazily, so check that the built cards are all from
/// [expected] (and that there are some), and that the list is [expected].
void expectShows(WidgetTester tester, List<String> expected) {
  final shown = shownIDs(tester);
  expect(shown, isNotEmpty);
  expect(expected.toSet().containsAll(shown), isTrue,
      reason: '$shown not all in $expected');
  expect({for (final e in ScheduledEvents.events) e.eventID}, expected.toSet());
}

Set<String> selectedSegments(WidgetTester tester) =>
    tester.widget<SegmentedButton<String>>(switcher).selected;

/// Simulates an app restart: same stored prefs, empty memory.
Future<void> restart() async {
  final stored = <String, Object>{
    for (final k in MySetting.prefs.getKeys()) k: MySetting.prefs.get(k)!
  };
  SharedPreferences.setMockInitialValues(stored);
  await MySetting.initSharedPreferences();
  ScheduledEvents.resetMemory();
}

void main() {
  late Directory docs;

  setUp(() async {
    docs = await setUpEventSources();
  });

  tearDown(() => tearDownEventSources(docs));

  /// Saves [sources] and fills A's and B's caches from the mock server, with
  /// distinct last-refreshed times (A: 3 days ago, B: 2 hours ago).
  Future<void> cacheAB(List<ScheduledEventsSource> sources) async {
    await EventSources.save(sources);
    await refreshFromMock(a);
    await refreshFromMock(b);
    ScheduledEvents.cacheFor(a).lastRefreshed =
        DateTime.now().subtract(const Duration(days: 3, minutes: 5));
    ScheduledEvents.cacheFor(b).lastRefreshed =
        DateTime.now().subtract(const Duration(hours: 2, minutes: 1));
  }

  // AC1 (intent 0017)
  testWidgets('three sources: one segment each, in order, above the header',
      (tester) async {
    phone(tester);
    await EventSources.save([b, customSource, a]);
    final selection = SourceSelection();
    await tester.pumpWidget(app(selection));
    await tester.pump();

    expect(switcher, findsOneWidget);
    final button = tester.widget<SegmentedButton<String>>(switcher);
    expect([for (final s in button.segments) s.value],
        [b.key, customSource.key, a.key]);
    expect(button.multiSelectionEnabled, isFalse);
    expect(button.emptySelectionAllowed, isFalse);

    // Under the app bar, above the existing header.
    final top = tester.getRect(switcher);
    expect(top.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
    expect(
        top.bottom,
        lessThanOrEqualTo(
            tester.getTopLeft(find.text('Update event data')).dy));
    expect(
        top.bottom,
        lessThanOrEqualTo(
            tester.getTopLeft(find.textContaining('No event data')).dy));
    await unmount(tester);
  });

  // AC2 (intent 0017)
  testWidgets('one source: no switcher', (tester) async {
    phone(tester);
    await EventSources.save([a]);
    final selection = SourceSelection();
    await tester.pumpWidget(app(selection));
    await tester.pump();
    expect(switcher, findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Update event data'), findsOneWidget);
    await unmount(tester);
  });

  // AC3 (intent 0017)
  testWidgets('short labels; full name is the tooltip and semantics label',
      (tester) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    await EventSources.save([a, customSource, unknown]);
    final selection = SourceSelection();
    await tester.pumpWidget(app(selection));
    await tester.pump();

    // The region's short name, not the full "US RUSA Region: PA: Eastern".
    expect(a.shortLabel, a.region.regionSubName);
    expect(a.shortLabel, 'Eastern');
    expect(a.fullDescription, contains('PA: Eastern'));
    expect(customSource.shortLabel, 'Custom');
    expect(unknown.shortLabel, '999999');
    for (final s in [a, customSource, unknown]) {
      expect(segment(s.shortLabel), findsOneWidget);
      expect(
          find.descendant(
              of: switcher, matching: find.byTooltip(s.fullDescription)),
          findsOneWidget);
      expect(find.bySemanticsLabel(s.fullDescription), findsOneWidget);
    }
    semantics.dispose();
    await unmount(tester);
  });

  // AC4 and AC9 (intent 0017): two cached sources with distinct mock feeds.
  testWidgets('switching shows the cached source with no network call',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => cacheAB([a, b])); // real file I/O
    final aIDs = ids(a), bIDs = ids(b);
    final aTime = ScheduledEvents.cacheFor(a).lastRefreshed;
    final bTime = ScheduledEvents.cacheFor(b).lastRefreshed;
    expect(aIDs, isNotEmpty);
    expect(bIDs, isNotEmpty);
    expect(bIDs.toSet().intersection(aIDs.toSet()), isEmpty);

    final requests = <Uri>[];
    final selection = SourceSelection();
    await http.runWithClient(() async {
      await tester.pumpWidget(app(selection));
      await tester.pump();
      expect(selectedSegments(tester), {a.key});
      expectShows(tester, aIDs);
      expect(find.text('Event data updated: 3 days ago'), findsOneWidget);

      await tester.tap(segment(b.shortLabel));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              requests.add(r.url);
              return http.Response('', 500);
            }));

    expect(requests, isEmpty);
    expect(selectedSegments(tester), {b.key});
    expect(selection.eventInfoSource.key, b.key);
    expect(EventSources.selected.key, b.key); // persisted
    expect(MySetting.prefs.getString('key-selected-event-source'), b.key);
    expectShows(tester, bIDs);
    expect(
        find.textContaining(RegExp(r'^Event data updated: 2(\.\d)? hrs ago$')),
        findsOneWidget);

    // Other sources unchanged.
    expect(ids(a), aIDs);
    expect(ScheduledEvents.cacheFor(a).lastRefreshed, aTime);
    expect(ScheduledEvents.cacheFor(b).lastRefreshed, bTime);

    // And back again.
    await tester.tap(segment(a.shortLabel));
    await tester.pumpAndSettle();
    expectShows(tester, aIDs);
    expect(find.text('Event data updated: 3 days ago'), findsOneWidget);
    await unmount(tester);
  });

  // AC5 (intent 0017)
  testWidgets('"Update event data" refreshes only the selected source',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => cacheAB([a, b])); // real file I/O
    await EventSources.select(b);
    final aIDs = ids(a);
    final aTime = ScheduledEvents.cacheFor(a).lastRefreshed;
    final bTime = ScheduledEvents.cacheFor(b).lastRefreshed!;

    final requested = <Uri>[];
    final selection = SourceSelection();
    await tester.pumpWidget(app(selection));
    await tester.pump();
    expect(selectedSegments(tester), {b.key});

    // The button's refresh runs in the mock-server zone; real file I/O (the
    // fixture read and the cache write) progresses during short runAsync
    // waits between pumps.
    await http.runWithClient(
        () => tester.tap(find.text('Update event data')),
        () => MockClient((r) async {
              requested.add(r.url);
              final res = await MockServer.client().get(r.url);
              return http.Response(res.body, res.statusCode);
            }));
    for (var i = 0;
        i < 100 && ScheduledEvents.cacheFor(b).lastRefreshed == bTime;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();

    expect(ScheduledEvents.cacheFor(b).lastRefreshed!.isAfter(bTime), isTrue);
    expect(requested, isNotEmpty);
    expect(requested.every((u) => u.path.contains(MockServer.altRegionID)),
        isTrue);
    expect(ids(a), aIDs);
    expect(ScheduledEvents.cacheFor(a).lastRefreshed, aTime);
    await unmount(tester);
  });

  // AC6 (intent 0017)
  testWidgets('five sources at 390 dp scroll sideways, no overflow',
      (tester) async {
    phone(tester);
    final sources = [
      a,
      b,
      customSource,
      regionSource('011101'),
      regionSource('011153'),
    ];
    await EventSources.save(sources);
    final selection = SourceSelection();
    await tester.pumpWidget(app(selection));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final last = segment(sources.last.shortLabel);
    // More than fits: the last segment starts off screen.
    expect(tester.getRect(last).right, greaterThan(390));

    await tester.dragUntilVisible(last,
        find.byKey(const Key('region-switcher-scroll')), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(last).right, lessThanOrEqualTo(390));
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selectedSegments(tester), {sources.last.key});
    expect(EventSources.selected.key, sources.last.key);
    await unmount(tester);

    // The selected segment is scrolled into view on build.
    await tester.pumpWidget(app(SourceSelection()));
    await tester.pumpAndSettle();
    final r = tester.getRect(last);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  // AC7 (intent 0017)
  group('the selection is restored after a restart', () {
    testWidgets('same source selected and shown', (tester) async {
      phone(tester);
      await EventSources.save([a, b, customSource]);
      final first = SourceSelection();
      await tester.runAsync(() => first.select(b)); // reads B's cache file
      first.dispose();

      await restart();
      final selection = SourceSelection();
      expect(selection.eventInfoSource.key, b.key);
      await tester.pumpWidget(app(selection));
      await tester.pump();
      expect(selectedSegments(tester), {b.key});
      await unmount(tester);
    });

    test('a removed selection falls back to the first source', () async {
      await EventSources.save([a, b, customSource]);
      await EventSources.select(b);
      // Stored list without B (as Settings would leave it).
      await EventSources.save([customSource, a]);
      await restart();
      expect(SourceSelection().eventInfoSource.key, customSource.key);
    });
  });

  // AC8 (intent 0017)
  group('Settings changes', () {
    testWidgets('the switcher follows add, remove and reorder', (tester) async {
      phone(tester);
      await EventSources.save([a]);
      final selection = SourceSelection();
      await tester.pumpWidget(app(selection));
      await tester.pump();
      expect(switcher, findsNothing);

      // Add: appears for two sources.
      await tester.runAsync(() => selection.setSources([a, b]));
      await tester.pump();
      expect(switcher, findsOneWidget);
      expect([
        for (final s
            in tester.widget<SegmentedButton<String>>(switcher).segments)
          s.value
      ], [
        a.key,
        b.key
      ]);

      // Add a third and reorder.
      await tester.runAsync(() => selection.setSources([customSource, b, a]));
      await tester.pump();
      expect([
        for (final s
            in tester.widget<SegmentedButton<String>>(switcher).segments)
          s.value
      ], [
        customSource.key,
        b.key,
        a.key
      ]);
      expect(selectedSegments(tester), {a.key}); // reorder keeps it

      // Remove the selected one: the first remaining is selected.
      await tester.runAsync(() => selection.setSources([customSource, b]));
      await tester.pump();
      expect(selectedSegments(tester), {customSource.key});

      // Remove down to one: disappears.
      await tester.runAsync(() => selection.setSources([b]));
      await tester.pump();
      expect(switcher, findsNothing);
      expect(selection.eventInfoSource.key, b.key);
      await unmount(tester);
    });

    test('select B, move A below C: B stays selected', () async {
      await EventSources.save([a, b, customSource]);
      final selection = SourceSelection();
      await selection.select(b);
      await selection.setSources([b, customSource, a]);
      expect(EventSources.selected.key, b.key);
      expect(selection.eventInfoSource.key, b.key);
      selection.dispose();
    });

    test('with no stored selection, a reorder keeps the shown (first) source',
        () async {
      await EventSources.save([a, b, customSource]);
      expect(EventSources.selected.key, a.key); // nothing stored yet
      final selection = SourceSelection();
      await selection.setSources([b, customSource, a]);
      expect(EventSources.selected.key, a.key);
      expect(selection.eventInfoSource.key, a.key);
      selection.dispose();
    });

    test('removing the selected source selects the first remaining one',
        () async {
      await EventSources.save([a, b, customSource]);
      final selection = SourceSelection();
      await selection.select(b);
      await selection.setSources([customSource, a]);
      expect(EventSources.selected.key, customSource.key);
      expect(selection.eventInfoSource.key, customSource.key);
      selection.dispose();
    });
  });
}
