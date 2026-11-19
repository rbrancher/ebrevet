// Controls and check-in screens on Material 3 (intent 0003).
//
// kMockMode is false under `flutter test`, so these tests stand in for the
// mock-mode seams themselves:
//  - RiderLocation is set from MockLocation directly, and the geolocator
//    method channel answers with MockLocation (so GPS Update succeeds).
//  - http goes to MockServer through http.runWithClient.
//  - path_provider points at a temp dir so MyActivatedEvents.save() works.

import 'dart:io';

import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/app_tokens.dart';
import 'package:ebrevet_card/checkin_status_page.dart';
import 'package:ebrevet_card/control_card.dart';
import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/controls_view_page.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/location.dart';
import 'package:ebrevet_card/map_icon_button.dart';
import 'package:ebrevet_card/mock/mock_location.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_activated_events.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

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

/// `.icon` / `.tonal` variants may be private subclasses; match with `is`.
Finder isA_<T>({bool skipOffstage = true}) =>
    find.byWidgetPredicate((w) => w is T, skipOffstage: skipOffstage);

/// Fill color the button actually renders with.
Color? fillOf(WidgetTester tester, Finder button) => tester
    .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first)
    .color;

ColorScheme schemeOf(WidgetTester tester, Type t) =>
    Theme.of(tester.element(find.byType(t).first)).colorScheme;

/// FilledButtons with primary emphasis. `FilledButton.tonal` is the same
/// class, so tell them apart by the fill they render with.
List<Element> primaryFilled(WidgetTester tester, Type page) {
  final scheme = schemeOf(tester, page);
  final all = isA_<FilledButton>(skipOffstage: false);
  return [
    for (final e in all.evaluate())
      if (fillOf(tester, find.byWidget(e.widget)) == scheme.primary) e
  ];
}

/// Text of a FilledButton's first Text descendant.
String? buttonLabel(WidgetTester tester, Element button) => tester
    .widget<Text>(find
        .descendant(
            of: find.byWidget(button.widget), matching: find.byType(Text))
        .first)
    .data;

/// Let real I/O (file save) and pumped frames interleave.
Future<void> settleIO(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Unmount so ControlsViewPage cancels its GPS timer, then let SnackBar
/// timers run out.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  late List<Event> events;
  late Directory docs;
  final activated = <ActivatedEvent>[];

  ActivatedEvent activate(Event e, StartStyle style) {
    final a =
        MyActivatedEvents.addActivate(e, riderID: '12345', startStyle: style);
    activated.add(a);
    return a;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Keep the check-in path free of dialogs and comment fetches; the
      // check-in itself is unchanged.
      // MySetting stores every value as a string.
      'key-allow-checkin-comment': 'false',
      'key-enable-post-checkin-dialog': 'false',
      'key-notify-comments': 'false',
    });
    await MySetting.initSharedPreferences();
    useMockServerForTests();
    // ActivatedEvent compares with DateTime.now(); date the feed to match.
    MockServer.now = DateTime.now;
    events = await mockEvents();
    ScheduledEvents.events = events;

    MockLocation.reset();
    RiderLocation.riderLocation = MockLocation.position;
    RiderLocation.lastLocationUpdate = DateTime.now();

    docs = Directory.systemTemp.createTempSync('ebrevet_test_');
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
        case 'getCurrentPosition':
          return MockLocation.position.toJson();
      }
      return null;
    });
  });

  tearDown(() {
    for (final a in activated) {
      MyActivatedEvents.deleteMyActivatedEvent(a);
    }
    activated.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(geolocatorChannel, null);
    RiderLocation.riderLocation = null;
    RiderLocation.lastLocationUpdate = null;
    ScheduledEvents.events = <Event>[];
    MockServer.now = DateTime.now;
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpControls(WidgetTester tester, Event event,
      {ThemeMode mode = ThemeMode.light}) async {
    await tester.pumpWidget(app(
        ControlsViewPage(event: event, style: ControlsViewStyle.live),
        mode: mode));
    await tester.pump(); // GPS update from initState completes
    await tester.pump();
  }

  // AC2 (intent 0003)
  group('control status mapping', () {
    final tokens = DayNight().dayTheme.extension<AppTokens>()!;

    ControlStatus? of(
            {bool checkedIn = false,
            bool dnf = false,
            bool skipped = false,
            ControlWindow window = ControlWindow.unknown}) =>
        controlStatusOf(
            checkedIn: checkedIn, dnf: dnf, skipped: skipped, window: window);

    test('checked in -> checkedIn pair', () {
      expect(of(checkedIn: true, window: ControlWindow.open),
          ControlStatus.checkedIn);
      expect(of(checkedIn: true, window: ControlWindow.closed),
          ControlStatus.checkedIn);
      expect(controlStatusColors(ControlStatus.checkedIn, tokens),
          tokens.checkedIn);
    });

    test('open window -> onTime pair', () {
      expect(of(window: ControlWindow.open), ControlStatus.onTime);
      expect(controlStatusColors(ControlStatus.onTime, tokens), tokens.onTime);
    });

    test('closing soon -> closingSoon pair', () {
      expect(controlStatusColors(ControlStatus.closingSoon, tokens),
          tokens.closingSoon);
    });

    test('closed window or skipped (missed) -> closed pair', () {
      expect(of(window: ControlWindow.closed), ControlStatus.closed);
      expect(
          of(skipped: true, window: ControlWindow.open), ControlStatus.closed);
      expect(controlStatusColors(ControlStatus.closed, tokens), tokens.closed);
    });

    test('DNF -> dnf pair', () {
      expect(of(dnf: true, window: ControlWindow.open), ControlStatus.dnf);
      expect(controlStatusColors(ControlStatus.dnf, tokens), tokens.dnf);
    });

    test('not yet open or unknown -> no status', () {
      expect(of(window: ControlWindow.notYetOpen), isNull);
      expect(of(window: ControlWindow.unknown), isNull);
    });
  });

  // AC2 + AC3 (intent 0003)
  testWidgets('close time uses AppTokens.numeric; status badge uses tokens',
      (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      final a = activate(event, StartStyle.massStart);
      // Rider has started: start control checked in at the event start.
      a.outcomes.setControlCheckInTime(
          event.startControlKey, event.startControlOpenTime);
      await pumpControls(tester, event);

      final close = find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data?.startsWith('Closes in') == true ||
              w.data?.startsWith('Closed ') == true));
      expect(close, findsWidgets);
      final style =
          tester.renderObject<RenderParagraph>(close.first).text.style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));

      final dist = find.textContaining('Dir: ').first;
      expect(
          tester.renderObject<RenderParagraph>(dist).text.style!.fontFeatures,
          contains(const FontFeature.tabularFigures()));

      // The checked-in start control's badge is drawn in the checkedIn pair.
      final tokens =
          AppTokens.of(tester.element(find.byType(ControlCard).first));
      final badge = tester
          .widget<ControlStatusBadge>(find.byType(ControlStatusBadge).first);
      expect(badge.status, ControlStatus.checkedIn);
      final box = tester.widget<Container>(find
          .descendant(
              of: find.byType(ControlStatusBadge).first,
              matching: find.byType(Container))
          .first);
      expect((box.decoration as BoxDecoration).color, tokens.checkedIn.color);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC4 (intent 0003)
  testWidgets('controls screen: one FilledButton, CHECK IN, when available',
      (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      activate(event, StartStyle.preRide);
      await pumpControls(tester, event);

      final filled = primaryFilled(tester, ControlsViewPage);
      expect(filled, hasLength(1));
      expect(buttonLabel(tester, filled.single), 'CHECK IN');

      final scheme = schemeOf(tester, ControlsViewPage);
      final gps = find.ancestor(
          of: find.text('GPS Update'), matching: isA_<FilledButton>());
      expect(gps, findsOneWidget);
      expect(fillOf(tester, gps), scheme.secondaryContainer);
      expect(
          find.ancestor(
              of: find.text('Resend Checkins'),
              matching: isA_<OutlinedButton>()),
          findsOneWidget);
      expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC4 (intent 0003)
  testWidgets('controls screen: no FilledButton when no control is available',
      (tester) async {
    await http.runWithClient(() async {
      MockLocation.moveTo(0, 0); // far from every control
      RiderLocation.riderLocation = MockLocation.position;
      final event = events.first;
      activate(event, StartStyle.preRide);
      await pumpControls(tester, event);

      expect(primaryFilled(tester, ControlsViewPage), isEmpty);
      expect(find.text('CHECK IN'), findsNothing);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC4 (intent 0003)
  testWidgets('check-in status screen has at most one FilledButton',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app(CheckinStatusPage(event: events.first)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(isA_<FilledButton>(skipOffstage: false).evaluate().length,
          lessThanOrEqualTo(1));
      expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC4 (intent 0003): dialog dismiss actions are TextButtons.
  testWidgets('control info dialog dismisses with a TextButton',
      (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      activate(event, StartStyle.preRide);
      await pumpControls(tester, event);
      await tester.tap(find.byIcon(Icons.info_outline).first);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(find.ancestor(of: find.text('OK'), matching: isA_<TextButton>()),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: isA_<FilledButton>()),
          findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await unmount(tester);
    }, MockServer.client);
  });

  // AC5 (intent 0003)
  testWidgets('GPS Update shows the GPS message as a SnackBar', (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      activate(event, StartStyle.preRide);
      await pumpControls(tester, event);
      // Let the snack from the initial GPS update in initState time out.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('GPS Update'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('GPS Location Updated'), findsOneWidget);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC6 (intent 0003): regression, check-in still records and reports once.
  testWidgets('CHECK IN records one check-in and posts one report',
      (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      final a = activate(event, StartStyle.preRide);
      final start = event.controls[event.startControlKey];
      expect(a.controlCheckInTime(start), isNull);
      await pumpControls(tester, event);

      await tester.tap(find.text('CHECK IN'));
      await settleIO(tester);

      expect(a.controlCheckInTime(start), isNotNull);
      final checked = [
        for (final c in event.controls)
          if (a.controlCheckInTime(c) != null) c.index
      ];
      expect(checked, [start.index]);
      final reports = MockServer.receivedReports
          .where((r) => r['control_index'] == '${start.index}')
          .toList();
      expect(reports, hasLength(1));
      expect(MockServer.receivedReports, hasLength(1));
      // The check-in snack may be queued behind the initial GPS snack.
      final snack =
          find.textContaining('Checked into Control ${start.index + 1}');
      for (var i = 0; i < 10 && snack.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(snack, findsOneWidget);
      expect(find.text('CHECK IN'), findsNothing);
      await unmount(tester);
    }, MockServer.client);
  });

  // AC7 (intent 0003)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        'controls screen meets contrast and tap-target guidelines '
        '($mode)', (tester) async {
      await http.runWithClient(() async {
        final handle = tester.ensureSemantics();
        final event = events.first;
        activate(event, StartStyle.preRide);
        await pumpControls(tester, event, mode: mode);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(ControlCard), findsWidgets);
        expect(find.text('CHECK IN'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
        await unmount(tester);
      }, MockServer.client);
    });
  }

  // AC9 (intent 0003)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        'FilledButton is primary, FilledButton.tonal is '
        'secondaryContainer ($mode)', (tester) async {
      await tester.pumpWidget(app(
          Scaffold(
            body: Column(children: [
              FilledButton(onPressed: () {}, child: const Text('primary')),
              FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
            ]),
          ),
          mode: mode));
      final scheme = schemeOf(tester, Scaffold);
      expect(scheme.brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      expect(
          fillOf(
              tester,
              find.ancestor(
                  of: find.text('primary'), matching: isA_<FilledButton>())),
          scheme.primary);
      expect(
          fillOf(
              tester,
              find.ancestor(
                  of: find.text('tonal'), matching: isA_<FilledButton>())),
          scheme.secondaryContainer);
      expect(scheme.primary, isNot(scheme.secondaryContainer));
    });
  }

  // AC8 (intent 0003)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('map icon uses colorScheme.primary ($mode)', (tester) async {
      await tester.pumpWidget(app(
          const Scaffold(body: MapIconButton(latitude: 40, longitude: -75)),
          mode: mode));
      final icon = tester.widget<Icon>(find.byIcon(Icons.map));
      expect(icon.color, schemeOf(tester, Scaffold).primary);
    });
  }
}
