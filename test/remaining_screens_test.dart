// Settings, certificate, log, past rides and side menu on Material 3
// (intent 0005).
//
// kMockMode is false under `flutter test`, so these tests stand in for the
// mock-mode seams themselves (as in controls_screen_test.dart):
//  - the event feed is the mock fixture, parsed through MockServer;
//  - RiderLocation comes from MockLocation, and the geolocator method
//    channel answers with MockLocation;
//  - path_provider points at a temp dir so MyActivatedEvents.save() works;
//  - http goes to MockServer through http.runWithClient.

import 'dart:io';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/app_tokens.dart';
import 'package:ebrevet_card/cert_page.dart';
import 'package:ebrevet_card/confetti_dialog.dart';
import 'package:ebrevet_card/control_card.dart';
import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/controls_view_page.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/event_card.dart';
import 'package:ebrevet_card/event_list_page.dart';
import 'package:ebrevet_card/location.dart';
import 'package:ebrevet_card/log_page.dart';
import 'package:ebrevet_card/mock/mock_location.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_activated_events.dart';
import 'package:ebrevet_card/my_activated_events_page.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/mylogger.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/settings_page.dart';
import 'package:ebrevet_card/side_menu.dart';
import 'package:ebrevet_card/signature.dart';
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
const modes = [ThemeMode.light, ThemeMode.dark];

Widget app(Widget home, {ThemeMode mode = ThemeMode.light, Color? seed}) {
  final dn =
      seed == null ? DayNight(mode: mode) : DayNight(mode: mode, color: seed);
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

/// `.tonal` variants may be private subclasses; match with `is`.
Finder isA_<T>({bool skipOffstage = true}) =>
    find.byWidgetPredicate((w) => w is T, skipOffstage: skipOffstage);

/// Fill color the button actually renders with.
Color? fillOf(WidgetTester tester, Finder button) => tester
    .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first)
    .color;

ColorScheme schemeOf(WidgetTester tester, Type t) =>
    Theme.of(tester.element(find.byType(t).first)).colorScheme;

/// FilledButtons drawn with primary emphasis (not `.tonal`).
List<Element> primaryFilled(WidgetTester tester, Type page) {
  final scheme = schemeOf(tester, page);
  return [
    for (final e in isA_<FilledButton>(skipOffstage: false).evaluate())
      if (fillOf(tester, find.byWidget(e.widget)) == scheme.primary) e
  ];
}

// Independent of AppTokens.contrastRatio so the check does not test itself.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Visibly different: hues at least 30 degrees apart, or a clear
/// lightness step.
bool visiblyDifferent(Color a, Color b) {
  final ha = HSLColor.fromColor(a).hue, hb = HSLColor.fromColor(b).hue;
  final dh = (ha - hb).abs();
  final hue = math.min(dh, 360 - dh);
  return hue >= 30 || contrast(a, b) >= 1.5;
}

AppTokens tokensFor(Color seed, Brightness b) {
  final dn = DayNight(color: seed);
  return (b == Brightness.light ? dn.dayTheme : dn.nightTheme)
      .extension<AppTokens>()!;
}

ColorScheme schemeFor(Color seed, Brightness b) {
  final dn = DayNight(color: seed);
  return (b == Brightness.light ? dn.dayTheme : dn.nightTheme).colorScheme;
}

/// Let pending timers and animations (confetti, shimmer) run without
/// waiting for them to settle; shimmer repeats forever.
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < d; t += step) {
    await tester.pump(step);
  }
}

/// Unmount, then let SnackBar and confetti timers run out.
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

  /// A ride with every control checked in at its open time, finished and
  /// uploaded after the finish.
  ActivatedEvent finished(Event e) {
    final a = activate(e, StartStyle.preRide);
    for (final c in e.controls) {
      a.outcomes.setControlCheckInTime(c.index, c.open);
    }
    a.outcomes.overallOutcome = OverallOutcome.finish;
    a.outcomes.lastUpload = e.controls.last.open.add(const Duration(hours: 1));
    return a;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'key-first-name': 'Test',
      'key-last-name': 'Rider',
      'key-rusa-id': '12345',
    });
    await MySetting.initSharedPreferences();
    useMockServerForTests();
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

  // AC1 (intent 0005): the default seed is a named token with the old value.
  test('default theme seed is AppTokens.defaultSeed, same blue as before', () {
    // ignore: deprecated_member_use
    expect(AppTokens.defaultSeed.value, Colors.blue.value);
    expect(DayNight().color, AppTokens.defaultSeed);
    expect(AppSettings.themeColor.defaultValue, AppTokens.defaultSeed);
    expect(DayNight().dayTheme.colorScheme,
        ColorScheme.fromSeed(seedColor: Colors.blue));
  });

  // AC2 (intent 0005)
  for (final mode in modes) {
    testWidgets(
        'certificate shows the finish code in AppTokens.numeric '
        'and meets text contrast ($mode)', (tester) async {
      final handle = tester.ensureSemantics();
      final a = finished(events.first);
      final certString = Signature.forCert(a).xyText;
      await tester.pumpWidget(app(CertificatePage(a), mode: mode));
      await pumpFor(tester, const Duration(seconds: 4));

      // Same text as before the restyle.
      final code = find.text('Finish Code: $certString');
      expect(code, findsOneWidget);
      final rich = tester.widget<Text>(code).textSpan! as TextSpan;
      final codeSpan = rich.children!.single as TextSpan;
      expect(codeSpan.text, certString);
      final tokens = AppTokens.of(tester.element(code));
      final scheme = Theme.of(tester.element(code)).colorScheme;
      expect(codeSpan.style!.fontFeatures,
          contains(const FontFeature.tabularFigures()));
      expect(codeSpan.style!.fontSize, tokens.numeric.fontSize);
      expect(codeSpan.style!.color, scheme.onSurface);
      expect(find.text('Finish Certificate'), findsOneWidget);
      expect(find.text(a.elapsedTimeStringVerbose), findsOneWidget);

      // Confetti on the page uses theme colors too (AC3).
      final confetti =
          tester.widget<ConfettiWidget>(find.byType(ConfettiWidget));
      expect(confetti.colors, [
        scheme.primary,
        scheme.secondary,
        scheme.tertiary,
        tokens.onTime.color,
      ]);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC3 (intent 0005)
  for (final mode in modes) {
    testWidgets('confetti dialog uses theme colors ($mode)', (tester) async {
      await tester.pumpWidget(app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const ConfettiDialog(
                        shouldConfetti: true, content: Text('Finished!')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          mode: mode));
      await tester.tap(find.text('open'));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('Finished!'), findsOneWidget);
      final ctx = tester.element(find.byType(ConfettiDialog));
      final scheme = Theme.of(ctx).colorScheme;
      final confetti =
          tester.widget<ConfettiWidget>(find.byType(ConfettiWidget));
      expect(confetti.colors, [
        scheme.primary,
        scheme.secondary,
        scheme.tertiary,
        AppTokens.of(ctx).onTime.color,
      ]);
      await tester.tap(find.text('CONTINUE'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(ConfettiDialog), findsNothing);
      await unmount(tester);
    });
  }

  // AC4 (intent 0005)
  for (final mode in modes) {
    testWidgets(
        'settings page: no primary FilledButton or ElevatedButton '
        '($mode)', (tester) async {
      await AppSettings.rusaID.setValue(AppSettings.magicRUSAID);
      await tester.pumpWidget(app(const SettingsPage(), mode: mode));
      await tester.pumpAndSettle();
      // Open every section so all of its actions are built.
      for (final title in [
        'Rider Settings',
        'Event Info Source',
        'Preferences',
        'Developer Options',
      ]) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(primaryFilled(tester, SettingsPage).length, lessThanOrEqualTo(1));
      expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
      for (final label in ['Clear All Settings', 'Clear Event List']) {
        expect(
            find.ancestor(
                of: find.text(label, skipOffstage: false),
                matching: isA_<OutlinedButton>(skipOffstage: false)),
            findsOneWidget,
            reason: label);
      }
      await unmount(tester);
    });

    testWidgets(
        'settings: Get Latest Region List is FilledButton.tonal '
        '($mode)', (tester) async {
      await AppSettings.scheduleEventsSourceID
          .setValue(ScheduleEventsSourceID.fromRegion);
      await tester.pumpWidget(app(const SettingsPage(), mode: mode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      final button = find.ancestor(
          of: find.text('Get Latest Region List', skipOffstage: false),
          matching: isA_<FilledButton>(skipOffstage: false));
      expect(button, findsOneWidget);
      expect(fillOf(tester, button),
          schemeOf(tester, SettingsPage).secondaryContainer);
      expect(primaryFilled(tester, SettingsPage), isEmpty);
      expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'required settings: Continue is the one FilledButton '
        '($mode)', (tester) async {
      await tester.pumpWidget(app(
          Scaffold(
            body: Builder(
              builder: (context) => Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.all(16),
                child: RequiredAppSettings(collapsed: false, onContinue: () {}),
              ),
            ),
          ),
          mode: mode));
      await tester.pumpAndSettle();
      final filled = primaryFilled(tester, RequiredAppSettings);
      expect(filled, hasLength(1));
      expect(
          find.descendant(
              of: find.byWidget(filled.single.widget),
              matching: find.text('Continue')),
          findsOneWidget);
      expect(isA_<ElevatedButton>(skipOffstage: false), findsNothing);
      await unmount(tester);
    });
  }

  // AC5 (intent 0005)
  for (final mode in modes) {
    testWidgets(
        'settings page meets contrast and tap-target guidelines '
        '($mode)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const SettingsPage(), mode: mode));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });

    testWidgets(
        'past rides page meets contrast and tap-target guidelines '
        '($mode)', (tester) async {
      final handle = tester.ensureSemantics();
      finished(events.first);
      await tester.pumpWidget(app(const MyActivatedEventsPage(), mode: mode));
      await tester.pumpAndSettle();
      expect(find.byType(EventCard), findsWidgets);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });

    testWidgets('log page meets contrast and tap-target guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      MyLogger.entry('remaining screens test log line');
      await tester.pumpWidget(app(const LogPage(), mode: mode));
      await tester.pumpAndSettle();
      expect(find.text('Log'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC6 (intent 0005)
  group('pending upload status pair', () {
    final seeds = <Color>[AppTokens.defaultSeed, Colors.green, Colors.purple];
    for (final b in Brightness.values) {
      for (final seed in seeds) {
        test('contrast and distinctness ($b, $seed)', () {
          final t = tokensFor(seed, b);
          final s = schemeFor(seed, b);
          expect(AppTokens.minIconContrast, 3.0);
          expect(contrast(t.pending.color, s.surface),
              greaterThanOrEqualTo(AppTokens.minIconContrast),
              reason: 'pending icon vs surface');
          expect(contrast(t.pending.color, t.pending.onColor),
              greaterThanOrEqualTo(4.5),
              reason: 'onPending vs pending');
          expect(visiblyDifferent(t.pending.color, t.checkedIn.color), isTrue,
              reason: 'pending vs checkedIn');
          expect(visiblyDifferent(t.pending.color, t.closingSoon.color), isTrue,
              reason: 'pending vs closingSoon');
        });
      }
      test('built from the fixed orange source ($b)', () {
        final orange = ColorScheme.fromSeed(
            seedColor: AppTokens.pendingSource, brightness: b);
        final t = tokensFor(AppTokens.defaultSeed, b);
        expect(t.pending, StatusColors(orange.primary, orange.onPrimary));
        // Independent of the theme seed.
        expect(tokensFor(Colors.purple, b).pending, t.pending);
        final hue = HSLColor.fromColor(AppTokens.pendingSource).hue;
        expect(hue, inInclusiveRange(20, 40)); // orange
      });
    }
  });

  // AC6 (intent 0005)
  for (final mode in modes) {
    testWidgets(
        'control card shows the pending color for an unposted '
        'check-in ($mode)', (tester) async {
      await http.runWithClient(() async {
        final event = events.first;
        final a = activate(event, StartStyle.preRide);
        // Recorded on the device, never posted (lastUpload is null).
        a.outcomes.setControlCheckInTime(event.startControlKey,
            DateTime.now().subtract(const Duration(minutes: 1)));
        expect(a.outcomes.lastUpload, isNull);
        await tester.pumpWidget(app(
            ControlsViewPage(event: event, style: ControlsViewStyle.live),
            mode: mode));
        await tester.pump();
        await tester.pump();

        final tokens =
            AppTokens.of(tester.element(find.byType(ControlCard).first));
        final icon = tester.widget<Icon>(find.byIcon(Icons.pending_sharp));
        expect(icon.color, tokens.pending.color);
        expect(icon.color, isNot(tokens.checkedIn.color));
        expect(find.byIcon(Icons.check_circle), findsNothing);

        // Once posted, the same control shows the checkedIn color.
        a.outcomes.lastUpload = DateTime.now();
        await tester.pumpWidget(app(
            ControlsViewPage(
                key: UniqueKey(), event: event, style: ControlsViewStyle.live),
            mode: mode));
        await tester.pump();
        await tester.pump();
        final posted = tester.widget<Icon>(find.byIcon(Icons.check_circle));
        expect(posted.color, tokens.checkedIn.color);
        expect(find.byIcon(Icons.pending_sharp), findsNothing);
        await unmount(tester);
      }, MockServer.client);
    });
  }

  // AC7 (intent 0005)
  for (final b in Brightness.values) {
    test('numericSmall: tabular figures, smaller than numeric ($b)', () {
      final t = tokensFor(AppTokens.defaultSeed, b);
      expect(t.numericSmall.fontFeatures,
          contains(const FontFeature.tabularFigures()));
      expect(
          t.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(t.numericSmall.fontSize, lessThan(t.numeric.fontSize!));
      // lerp / copyWith carry the new fields.
      expect(t.copyWith().numericSmall, t.numericSmall);
      expect(t.lerp(t, 0.5).pending, t.pending);
    });
  }

  // AC7 (intent 0005)
  testWidgets('control card detail lines use numericSmall', (tester) async {
    await http.runWithClient(() async {
      final event = events.first;
      final a = activate(event, StartStyle.massStart);
      a.outcomes.setControlCheckInTime(
          event.startControlKey, event.startControlOpenTime);
      await tester.pumpWidget(
          app(ControlsViewPage(event: event, style: ControlsViewStyle.live)));
      await tester.pump();
      await tester.pump();
      final tokens =
          AppTokens.of(tester.element(find.byType(ControlCard).first));
      final style = tester
          .renderObject<RenderParagraph>(find.textContaining('Dir: ').first)
          .text
          .style!;
      expect(style.fontSize, tokens.numericSmall.fontSize);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      await unmount(tester);
    }, MockServer.client);
  });

  // AC8 (intent 0005)
  Widget menuHost({ThemeMode mode = ThemeMode.light}) => app(
      const Scaffold(
        drawer: SideMenuDrawer(),
        body: SizedBox.expand(),
      ),
      mode: mode);

  Future<void> openMenu(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  const entries = [
    'Settings',
    'My Rides',
    'Available Events',
    'Activity Log',
    'About eBrevet',
  ];

  for (final mode in modes) {
    testWidgets('side menu keeps every entry in order ($mode)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(menuHost(mode: mode));
      await openMenu(tester);
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('eBrevet Main Menu'), findsOneWidget);
      double? lastY;
      for (final label in entries) {
        final f = find.text(label);
        expect(f, findsOneWidget, reason: label);
        final y = tester.getTopLeft(f).dy;
        if (lastY != null) expect(y, greaterThan(lastY), reason: label);
        lastY = y;
      }
      await tester.tap(find.text('Available Events'));
      await tester.pumpAndSettle();
      for (final filter in EventFilter.values) {
        expect(find.text(filter.description), findsOneWidget,
            reason: filter.description);
      }
      // Header text sits on primaryContainer.
      final scheme = schemeOf(tester, Drawer);
      final header = tester.widget<DrawerHeader>(find.byType(DrawerHeader));
      expect(
          (header.decoration as BoxDecoration).color, scheme.primaryContainer);
      final title = tester
          .renderObject<RenderParagraph>(find.text('eBrevet Main Menu'))
          .text
          .style!;
      expect(title.color, scheme.onPrimaryContainer);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC8 (intent 0005): each entry still goes to the same place.
  final destinations = <String, Finder Function()>{
    'Settings': () => find.byType(SettingsPage),
    'My Rides': () => find.byType(MyActivatedEventsPage),
    'Activity Log': () => find.byType(LogPage),
    'About eBrevet': () => find.byType(AboutDialog),
  };
  for (final d in destinations.entries) {
    testWidgets('side menu "${d.key}" opens its page', (tester) async {
      await tester.pumpWidget(menuHost());
      await openMenu(tester);
      await tester.tap(find.text(d.key));
      await tester.pumpAndSettle();
      expect(d.value(), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
      await unmount(tester);
    });
  }

  testWidgets('side menu event filters open the event list', (tester) async {
    await http.runWithClient(() async {
      for (final filter in EventFilter.values) {
        await tester.pumpWidget(menuHost());
        await openMenu(tester);
        await tester.tap(find.text('Available Events'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(filter.description));
        await pumpFor(tester, const Duration(seconds: 1));
        final page = tester
            .widget<ScheduledEventsPage>(find.byType(ScheduledEventsPage));
        expect(page.eventFilter, filter);
        await unmount(tester);
      }
    }, MockServer.client);
  });
}
