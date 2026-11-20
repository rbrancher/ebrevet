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
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

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

  // AC10 (intent 0009): slice (a) draws the sketch locally and adds no
  // dependency; the map package arrives in slice (b).
  test('no map dependency in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('flutter_map')));
    expect(pubspec, isNot(contains('latlong2')));
  });

  // AC7 (intent 0002), AC10 (intent 0009): cards now include the route
  // sketch.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('event list meets contrast and tap-target guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(eventList(), mode: mode));
      await tester.pump();
      expect(find.byType(EventCard), findsWidgets);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }
}
