// Profile page, app bar avatar, drawer link and mock demo rides
// (intent 0006).
//
// kMockMode is false under `flutter test`, so as in
// remaining_screens_test.dart the geolocator and path_provider channels are
// mocked and http goes to MockServer through http.runWithClient.

import 'dart:io';

import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/app_tokens.dart';
import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/files.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_activated_events.dart';
import 'package:ebrevet_card/my_activated_events_page.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/profile_page.dart';
import 'package:ebrevet_card/profile_stats.dart';
import 'package:ebrevet_card/rider_edit_page.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/side_menu.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'style_guardrail_test.dart' show countViolations;
import 'support/fixtures.dart';

const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const modes = [ThemeMode.light, ThemeMode.dark];

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

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < d; t += step) {
    await tester.pump(step);
  }
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> setRider(String first, String last, String id) async {
  SharedPreferences.setMockInitialValues({
    'key-first-name': first,
    'key-last-name': last,
    'key-rusa-id': id,
  });
  await MySetting.initSharedPreferences();
}

void main() {
  late List<Event> events;
  late Directory docs;

  /// 200 x2 (one a pre-ride), 300, 1000; plus a DNF and another rider's
  /// ride, which do not count.
  List<ActivatedEvent> fixtureRides() => [
        fixtureRide(events.first, km: 200),
        fixtureRide(events.first, km: 200, startStyle: StartStyle.preRide),
        fixtureRide(events.first, km: 300),
        fixtureRide(events.first, km: 1000),
        fixtureRide(events.first, km: 600, outcome: OverallOutcome.dnf),
        fixtureRide(events.first, km: 400, riderID: '99999'),
      ];

  setUp(() async {
    await setRider('Test', 'Rider', '12345');
    useMockServerForTests();
    MockServer.now = DateTime.now;
    events = await mockEvents();
    ScheduledEvents.events = events;

    docs = Directory.systemTemp.createTempSync('ebrevet_profile_test_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return docs.path;
    });
    messenger.setMockMethodCallHandler(geolocatorChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
        case 'requestPermission':
          return 2; // whileInUse
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(geolocatorChannel, null);
    ScheduledEvents.events = <Event>[];
    MockServer.now = DateTime.now;
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  // AC7 (intent 0006)
  for (final mode in modes) {
    testWidgets('profile page shows identity, stats and distances ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(app(ProfilePage(rides: fixtureRides()), mode: mode));
      await tester.pumpAndSettle();

      // Medium or large top app bar.
      expect(find.byType(SliverAppBar), findsOneWidget);
      expect(find.text('Profile'), findsWidgets);
      expect(tester.getTopLeft(find.byType(CircleAvatar)).dy,
          greaterThanOrEqualTo(112));

      // Read-only body: the only edit control is the app bar Edit action
      // (intent 0007, AC4).
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.byIcon(Icons.edit)),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      // Header: initials avatar, name most prominent, Rider ID.
      expect(
          find.descendant(
              of: find.byType(CircleAvatar), matching: find.text('TR')),
          findsOneWidget);
      expect(find.text('Test Rider'), findsOneWidget);
      expect(find.text('Rider ID: 12345'), findsOneWidget);
      final nameSize = tester
          .renderObject<RenderParagraph>(find.text('Test Rider'))
          .text
          .style!
          .fontSize!;
      for (final p in tester.renderObjectList<RenderParagraph>(find.descendant(
          of: find.byType(ListTile), matching: find.byType(Text)))) {
        expect(p.text.style?.fontSize ?? 0, lessThanOrEqualTo(nameSize));
      }

      // Stat cards: 4 rides, 1700 km, longest 1000, in AppTokens.numeric.
      final tokens = AppTokens.of(tester.element(find.byType(ProfilePage)));
      for (final v in ['4', '1700', '1000']) {
        final f =
            find.descendant(of: find.byType(Card), matching: find.text(v));
        expect(f, findsOneWidget, reason: v);
        final style = tester.renderObject<RenderParagraph>(f).text.style!;
        expect(style.fontSize, tokens.numeric.fontSize, reason: v);
        expect(
            style.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      expect(find.text('Rides'), findsOneWidget);
      expect(find.text('Total km'), findsOneWidget);
      expect(find.text('Longest ride (km)'), findsOneWidget);

      // Distances completed: all seven buckets in order.
      expect(find.text('Distances completed'), findsOneWidget);
      const expected = {
        'Populaire': 'Not yet',
        '200 km': '2',
        '300 km': '1',
        '400 km': 'Not yet',
        '600 km': 'Not yet',
        '1000 km': '1',
        '1200+ km': 'Not yet',
      };
      double? lastY;
      for (final e in expected.entries) {
        final tile = find.ancestor(
            of: find.text(e.key), matching: find.byType(ListTile));
        expect(tile, findsOneWidget, reason: e.key);
        expect(find.descendant(of: tile, matching: find.text(e.value)),
            findsOneWidget,
            reason: e.key);
        final y = tester.getTopLeft(tile).dy;
        if (lastY != null) expect(y, greaterThan(lastY), reason: e.key);
        lastY = y;
      }
      expect(find.text('Not yet'), findsNWidgets(4));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC6 (intent 0006)
  for (final mode in modes) {
    testWidgets('profile page shows an empty state, not zeros ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(
          ProfilePage(rides: [
            fixtureRide(events.first, km: 300, outcome: OverallOutcome.dnf),
            fixtureRide(events.first, km: 300, riderID: '99999'),
          ]),
          mode: mode));
      await tester.pumpAndSettle();
      expect(find.text('No finished rides yet'), findsOneWidget);
      expect(find.text('Total km'), findsNothing);
      expect(find.text('0'), findsNothing);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC8 (intent 0006)
  testWidgets('profile page says stats are from this phone, not lifetime',
      (tester) async {
    await tester.pumpWidget(app(ProfilePage(rides: fixtureRides())));
    await tester.pumpAndSettle();
    final note = find.textContaining('rides saved on this phone');
    expect(note, findsOneWidget);
    final text = tester.widget<Text>(note).data!;
    expect(
        text,
        contains('pruned after '
            '${AppSettings.keepPastEventMonths.value} months'));
    expect(text, contains('"keep past events"'));
    expect(text, contains('not lifetime totals'));
    await unmount(tester);
  });

  // AC9 (intent 0006)
  testWidgets('profile page links to My Rides', (tester) async {
    await tester.pumpWidget(app(ProfilePage(rides: fixtureRides())));
    await tester.pumpAndSettle();
    final link = find.widgetWithText(ListTile, 'My Rides');
    await tester.scrollUntilVisible(link, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(MyActivatedEventsPage), findsOneWidget);
    await unmount(tester);
  });

  // AC10 (intent 0006)
  Future<void> pumpEventList(WidgetTester tester) async {
    await tester.pumpWidget(app(const ScheduledEventsPage()));
    await pumpFor(tester, const Duration(seconds: 1));
  }

  final variants = {
    'initials avatar': ['Test', 'Rider', 'TR'],
    'account icon when no name is set': ['', '', ''],
  };
  for (final v in variants.entries) {
    testWidgets('event list app bar ends with a profile action (${v.key})',
        (tester) async {
      await http.runWithClient(() async {
        await setRider(v.value[0], v.value[1], '12345');
        final handle = tester.ensureSemantics();
        await pumpEventList(tester);

        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        final actions = appBar.actions!;
        expect(actions.last, isA<ProfileAvatarButton>());
        final toggle = actions[actions.length - 2] as IconButton;
        expect(toggle.icon, isA<Icon>()); // day/night toggle
        final profile = find.byType(ProfileAvatarButton);
        final dayNight = find.byWidget(toggle);
        expect(tester.getCenter(profile).dx,
            greaterThan(tester.getCenter(dayNight).dx));

        if (v.value[2].isEmpty) {
          expect(
              find.descendant(
                  of: profile, matching: find.byIcon(Icons.account_circle)),
              findsOneWidget);
          expect(
              find.descendant(of: profile, matching: find.byType(CircleAvatar)),
              findsNothing);
        } else {
          expect(
              find.descendant(
                  of: find.descendant(
                      of: profile, matching: find.byType(CircleAvatar)),
                  matching: find.text(v.value[2])),
              findsOneWidget);
        }

        expect(find.byTooltip('Profile'), findsOneWidget);
        expect(find.bySemanticsLabel('Profile'), findsOneWidget);
        expect(
            tester.getSemantics(find.bySemanticsLabel('Profile')),
            matchesSemantics(
                label: 'Profile',
                isButton: true,
                hasTapAction: true,
                hasFocusAction: true,
                hasEnabledState: true,
                isEnabled: true,
                isFocusable: true));
        final size = tester.getSize(
            find.descendant(of: profile, matching: find.byType(IconButton)));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        await tester.tap(profile);
        await tester.pumpAndSettle();
        expect(find.byType(ProfilePage), findsOneWidget);
        handle.dispose();
        await unmount(tester);
      }, MockServer.client);
    });
  }

  // AC11 (intent 0006)
  testWidgets('drawer rider line opens the Profile page', (tester) async {
    await tester.pumpWidget(app(const Scaffold(
      drawer: SideMenuDrawer(),
      body: SizedBox.expand(),
    )));
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rider: Test Rider (12345)'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    await unmount(tester);
  });

  // AC12 (intent 0006)
  group('mock demo rides', () {
    test('finished rides for the demo rider on 2-3 distances, plus a DNF',
        () async {
      final rides = (await MockServer.demoRides()).values.toList();
      expect(rides.every((r) => r.riderID == MockServer.demoRiderID), isTrue);
      expect(
          rides.where((r) => r.outcomes.overallOutcome == OverallOutcome.dnf),
          hasLength(1));
      expect(rides.every((r) => r.event.eventID.endsWith('-demo')), isTrue);
      expect(
          rides.every((r) => r.event.startDateTime!.isBefore(DateTime.now())),
          isTrue);

      final stats = ProfileStats.from(rides, MockServer.demoRiderID);
      expect(stats.isEmpty, isFalse);
      final done = stats.buckets.values.where((n) => n > 0).length;
      expect(done, inInclusiveRange(2, 3));
      final dnf = rides
          .firstWhere((r) => r.outcomes.overallOutcome == OverallOutcome.dnf);
      expect(stats.rides, rides.length - 1);
      expect(stats.buckets[DistanceBucket.of(dnf.event.distance)], 0);
    });

    test('seeding adds missing demo rides and keeps saved rides', () async {
      final storage = FileStorage(AppSettings.pastEventsFileName);
      final own = fixtureRide(events.first, km: 300);
      await storage.writeJSON({own.event.eventID: own.toJson()});

      await MockServer.seedDemoRides();
      await MockServer.seedDemoRides(); // idempotent
      final saved = await storage.readJSON();
      final demo = await MockServer.demoRides();
      expect(saved.keys, containsAll([own.event.eventID, ...demo.keys]));
      expect(saved.length, demo.length + 1);

      expect(await MyActivatedEvents.load(), demo.length + 1);
      for (final a in MyActivatedEvents.myActivatedEventsList) {
        MyActivatedEvents.deleteMyActivatedEvent(a);
      }
    });

    test('seeding runs only in mock mode', () {
      final main = File('lib/main.dart').readAsStringSync();
      final calls = RegExp(r'seedDemoRides').allMatches(main).toList();
      expect(calls, hasLength(1));
      final guard = main.lastIndexOf('if (kMockMode)', calls.single.start);
      expect(guard, greaterThanOrEqualTo(0));
      // Nothing closes the guarded block between the check and the call.
      expect(main.substring(guard, calls.single.start).contains('}'), isFalse);
      final others = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.contains('mock') &&
              !f.path.endsWith('main.dart') &&
              f.readAsStringSync().contains('seedDemoRides'))
            f.path
      ];
      expect(others, isEmpty);
    });
  });

  // AC13 (intent 0006)
  test('profile files use theme roles and tokens only', () {
    for (final path in [
      'lib/profile_page.dart',
      'lib/profile_stats.dart',
      'lib/side_menu.dart',
      'lib/event_list_page.dart',
    ]) {
      expect(countViolations(File(path).readAsStringSync()), 0, reason: path);
    }
  });

  // AC4 (intent 0007): Edit opens the rider form; after Save the header,
  // the event list avatar and the drawer header show the new values.
  testWidgets('profile Edit opens RiderEditPage and Save updates the header',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const ScheduledEventsPage()));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.byType(ProfileAvatarButton));
      await tester.pumpAndSettle();
      expect(find.text('Test Rider'), findsOneWidget);
      expect(find.text('TR'), findsOneWidget);
      expect(find.text('Rider ID: 12345'), findsOneWidget);

      final edit = find.widgetWithIcon(IconButton, Icons.edit);
      expect(find.descendant(of: find.byType(AppBar), matching: edit),
          findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(RiderEditPage), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Ann');
      await tester.enterText(find.byType(TextFormField).at(1), 'Other');
      await tester.enterText(find.byType(TextFormField).at(2), '777');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RiderEditPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Ann Other'), findsOneWidget);
      expect(find.text('AO'), findsOneWidget);
      expect(find.text('Rider ID: 777'), findsOneWidget);

      // Back to the event list: the app bar avatar shows the new initials.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(ProfileAvatarButton), matching: find.text('AO')),
          findsOneWidget);
      // And the drawer header shows the new rider.
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      expect(find.text('Rider: Ann Other (777)'), findsOneWidget);
      await unmount(tester);
    }, MockServer.client);
  });
}
