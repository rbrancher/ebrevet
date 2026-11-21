// Ride summary sheet content and links (intent 0013). Nothing here touches
// the network or launches anything.

import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/control.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/ride_summary_sheet.dart';
import 'package:ebrevet_card/route_map_page.dart';
import 'package:ebrevet_card/utility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'event_list_screen_test.dart' show app, unmount;
import 'route_map_page_test.dart' show lineControls, setSize;
import 'support/fake_tiles.dart';
import 'support/fixtures.dart';

/// A copy of [base] with the given feed fields replaced.
Event withFields(Event base, Map<String, dynamic> fields,
    {List<Control>? controls}) {
  final json = jsonDecode(jsonEncode(base.toJson)) as Map<String, dynamic>
    ..addAll(fields);
  final e = Event.fromJson(json);
  if (controls != null) {
    e.controls
      ..clear()
      ..addAll(controls);
  }
  return e;
}

/// The sheet alone, filling a page body, opened to [size].
class SheetHost extends StatefulWidget {
  final Event event;
  final double size;
  final Control? highlighted;
  const SheetHost(this.event,
      {super.key, this.size = RideSummarySheet.expandedSize, this.highlighted});

  @override
  State<SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<SheetHost> {
  final controller = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.isAttached) controller.jumpTo(widget.size);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Map')),
        body: RideSummarySheet(
          event: widget.event,
          controller: controller,
          highlighted: widget.highlighted,
          onControlTap: (_) {},
        ),
      );
}

Finder get surface => find.byKey(RideSummarySheet.surfaceKey);

/// Any TextButton; `.icon` builds a private subclass.
Finder get textButton => find.byWidgetPredicate((w) => w is TextButton);

/// [text] is found in the sheet and lies fully inside its visible part.
void expectVisible(WidgetTester tester, Finder text) {
  final f = find.descendant(of: surface, matching: text);
  expect(f, findsOneWidget, reason: '$text');
  final r = tester.getRect(f);
  final s = tester.getRect(surface);
  expect(s.intersect(r), r, reason: '$text not visible');
}

void main() {
  late List<Event> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MySetting.initSharedPreferences();
    useMockServerForTests();
    events = await mockEvents();
  });

  tearDown(() {
    RideSummarySheet.phoneLauncher = RideSummarySheet.defaultPhoneLauncher();
  });

  Event sample({Map<String, dynamic> fields = const {}}) => withFields(
        events.first,
        {
          'name': 'Sample Hills',
          'distance': 200,
          'sanction': 'ACP',
          'type': 'brevet',
          'start_city': 'Doylestown',
          'start_state': 'PA',
          'gravel_distance': 0,
          'cue_version': 3,
          'organizer_name': 'Pat Organizer',
          'organizer_phone': '555-0100',
          ...fields,
        },
        controls: lineControls(),
      );

  // AC5 (intent 0013)
  testWidgets('expanded sheet shows every summary field of a mock event',
      (tester) async {
    await setSize(tester, const Size(500, 1400));
    final event = sample();
    await tester.pumpWidget(app(SheetHost(event)));
    await tester.pumpAndSettle();
    final region = Region(regionID: event.regionID);
    final start = event.startDateTime!.toLocal();
    for (final t in [
      'Sample Hills 200K',
      '${event.dateTime} ${start.timeZoneName}',
      'Ride details',
      'ACP brevet',
      'Time limit: 1h00 (start to finish)',
      'Start location: Doylestown, PA',
      'Club: ${region.clubName}',
      'Region: ${region.regionName}',
      'Cue version: 3',
      'Organizer: Pat Organizer',
      'Phone: 555-0100',
      '3 controls',
    ]) {
      expectVisible(tester, find.text(t));
    }
    // Each control: name, distance and, if timed, open and close times.
    for (final c in event.controls) {
      expectVisible(tester, find.text(c.name));
      final km = '${RideSummarySheet.controlKm(c)} km';
      final times = ' · ${Utility.toBriefDateTimeString(c.open)}'
          ' – ${Utility.toBriefDateTimeString(c.close)}';
      expectVisible(
          tester, find.text(event.isUntimedControl(c) ? km : '$km$times'));
    }
    // The photo control is untimed: no times.
    expect(event.isUntimedControl(event.controls[1]), isTrue);
    expect(RideSummarySheet.controlKm(event.controls[2]), '32.2');
    // Gravel 0: no gravel line.
    expect(find.textContaining('Gravel'), findsNothing);
    expect(find.text('No cue sheet'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  // PR 41 review: section titles rank between the headline and the body,
  // and the controls are a numbered Material 3 list, not cards.
  testWidgets('section titles and a numbered control list', (tester) async {
    final handle = tester.ensureSemantics();
    await setSize(tester, const Size(500, 1400));
    final event = sample();
    await tester.pumpWidget(app(SheetHost(event)));
    await tester.pumpAndSettle();
    final textTheme = Theme.of(tester.element(surface)).textTheme;
    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;
    final headline = sizeOf('Sample Hills 200K');
    for (final title in ['Ride details', '3 controls']) {
      expect(sizeOf(title), textTheme.titleMedium!.fontSize);
      expect(sizeOf(title), lessThan(headline));
      expect(sizeOf(title), greaterThan(sizeOf('ACP brevet')));
      // Not below a list item's title: as large, and heavier.
      final item = tester.widget<Text>(find.text(event.controls.first.name));
      final style = tester.widget<Text>(find.text(title)).style!;
      expect(style.fontSize, greaterThanOrEqualTo(item.style!.fontSize!));
      expect(style.fontWeight!.value,
          greaterThan((item.style!.fontWeight ?? FontWeight.w400).value));
      expect(tester.getSemantics(find.text(title)),
          matchesSemantics(label: title, isHeader: true));
    }
    expect(find.byType(Divider), findsNWidgets(2));
    // One list item per control, numbered from 1 in route order.
    final rows = find.byType(ControlRow);
    expect(rows, findsNWidgets(event.controls.length));
    for (var i = 0; i < event.controls.length; i++) {
      final row = find.byWidgetPredicate(
          (w) => w is ControlRow && identical(w.control, event.controls[i]));
      expect(tester.widget<ControlRow>(row).number, i + 1);
      final tile = find.descendant(of: row, matching: find.byType(ListTile));
      expect(tile, findsOneWidget);
      final leading = tester.widget<ListTile>(tile).leading!;
      expect(
          find.descendant(
              of: find.byWidget(leading), matching: find.text('${i + 1}')),
          findsOneWidget);
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    }
    expect(find.byType(Card), findsNothing);
    handle.dispose();
    await unmount(tester);
  });

  // PR 41 review: the card's buttons beside the title and its ride row
  // below it, when the page supplies them.
  testWidgets('card actions beside the title and below it', (tester) async {
    await setSize(tester, const Size(500, 1400));
    final event = sample();
    final controller = DraggableScrollableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(Scaffold(
      body: RideSummarySheet(
        event: event,
        controller: controller,
        headerActions: (_) => IconButton(
            onPressed: () {},
            tooltip: 'Event Info',
            icon: const Icon(Icons.info_outline)),
        rideActions: (_) =>
            FilledButton(onPressed: () {}, child: const Text('RIDE')),
      ),
    )));
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Sample Hills 200K'));
    final info = tester.getRect(find.byTooltip('Event Info'));
    final ride = tester.getRect(find.text('RIDE'));
    expect(info.left, greaterThan(title.right - 1));
    expect(info.top, lessThan(title.bottom));
    expect(ride.top, greaterThan(title.bottom));
    expect(
        ride.bottom, lessThan(tester.getRect(find.text('Ride details')).top));
    expectVisible(tester, find.text('RIDE'));
    await unmount(tester);
  });

  // AC5 (intent 0013)
  testWidgets('gravel shown above 0, "No cue sheet", unknown values omitted',
      (tester) async {
    await setSize(tester, const Size(500, 1400));
    final event = sample(fields: {
      'gravel_distance': 40,
      'cue_version': 0,
      'organizer_name': '?',
      'organizer_phone': '?',
      'sanction': '?',
      'type': '?',
    });
    await tester.pumpWidget(app(SheetHost(event)));
    await tester.pumpAndSettle();
    expectVisible(tester, find.text('Gravel: 40 km'));
    expectVisible(tester, find.text('No cue sheet'));
    expect(find.textContaining('Cue version'), findsNothing);
    expect(find.textContaining('Organizer'), findsNothing);
    expect(find.textContaining('Phone'), findsNothing);
    expect(find.textContaining('?'), findsNothing);
    await unmount(tester);
  });

  // AC5 (intent 0013): the mock feed's events render without error.
  testWidgets('every mock event renders its summary', (tester) async {
    await setSize(tester, const Size(500, 1400));
    for (final event in events) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(SheetHost(event)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: event.name);
      expectVisible(tester, find.text('${event.controls.length} controls'));
      expect(find.byType(ControlRow), findsNWidgets(event.controls.length));
    }
    await unmount(tester);
  });

  group('organizer phone (AC6, intent 0013)', () {
    // AC6 (intent 0013)
    test('no launcher under flutter test (and on web); url_launcher present',
        () {
      expect(RideSummarySheet.defaultPhoneLauncher(), isNull);
      expect(RideSummarySheet.phoneLauncher, isNull);
      expect(
          File('pubspec.yaml').readAsStringSync(), contains('url_launcher:'));
      expect(RideSummarySheet.telUri('(555) 010-0100').toString(),
          'tel:5550100100');
      expect(
          RideSummarySheet.telUri('+1 555 0100').toString(), 'tel:+15550100');
    });

    // AC6 (intent 0013)
    testWidgets('plain text where launching is unsupported', (tester) async {
      await setSize(tester, const Size(500, 1400));
      await tester.pumpWidget(app(SheetHost(sample())));
      await tester.pumpAndSettle();
      expectVisible(tester, find.text('Phone: 555-0100'));
      expect(textButton, findsNothing);
      await unmount(tester);
    });

    // AC6 (intent 0013)
    testWidgets('a tel: link through the seam, 48 dp target', (tester) async {
      final handle = tester.ensureSemantics();
      final launched = <Uri>[];
      RideSummarySheet.phoneLauncher = (uri) async {
        launched.add(uri);
        return true;
      };
      await setSize(tester, const Size(500, 1400));
      await tester.pumpWidget(app(SheetHost(sample())));
      await tester.pumpAndSettle();
      final link =
          find.ancestor(of: find.text('555-0100'), matching: textButton);
      expect(link, findsOneWidget);
      expect(find.text('Phone: 555-0100'), findsNothing);
      final size = tester.getSize(link);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(link);
      await tester.pump();
      expect(launched, [Uri.parse('tel:5550100')]);
      handle.dispose();
      await unmount(tester);
    });

    // AC6 (intent 0013)
    testWidgets('missing phone: no link, no text', (tester) async {
      RideSummarySheet.phoneLauncher = (uri) async => fail('launched $uri');
      await setSize(tester, const Size(500, 1400));
      for (final phone in ['', '?']) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
            app(SheetHost(sample(fields: {'organizer_phone': phone}))));
        await tester.pumpAndSettle();
        expect(textButton, findsNothing);
        expect(find.textContaining('Phone'), findsNothing);
      }
      await unmount(tester);
    });
  });

  // AC9 (intent 0013)
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('theme colours; contrast and tap-target guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      RideSummarySheet.phoneLauncher = (uri) async => true;
      await setSize(tester, const Size(500, 1400));
      final event = sample(fields: {'gravel_distance': 20});
      await tester.pumpWidget(
          app(SheetHost(event, highlighted: event.controls.last), mode: mode));
      await tester.pumpAndSettle();
      final scheme = Theme.of(tester.element(surface)).colorScheme;
      expect(
          tester.widget<Material>(surface).color, scheme.surfaceContainerLow);
      final highlighted = find.descendant(
          of: find.byWidgetPredicate((w) => w is ControlRow && w.highlighted),
          matching: find.byType(Material));
      expect(tester.widget<Material>(highlighted.first).color,
          scheme.secondaryContainer);
      expect(find.byType(ControlDetails), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC9 (intent 0013): the full page with the sheet expanded and a
  // highlighted control, light and dark.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('page with expanded sheet meets guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      // Tall enough that the half-open sheet shows the whole list: the tap
      // target guideline flags any row partly scrolled out of a list.
      await setSize(tester, const Size(500, 1400));
      final event = sample();
      await tester.pumpWidget(app(
          RouteMapPage(event: event, tileProvider: FakeTileProvider()),
          mode: mode));
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byWidgetPredicate(
              (w) => w is ControlMarker && w.control.name == 'Finish diner'),
          matching: find.byType(GestureDetector)));
      await tester.pumpAndSettle();
      expect(find.byType(ControlDetails), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await unmount(tester);
    });
  }

  // AC9 (intent 0013): no hard-coded colours or font sizes in the sheet
  // (the style guardrail test covers all of lib/; this pins the new file).
  test('sheet source uses theme colours only', () {
    final src = File('lib/ride_summary_sheet.dart').readAsStringSync();
    expect(RegExp(r'Colors\.(?!transparent)').hasMatch(src), isFalse);
    expect(src, isNot(contains('Color(0x')));
    expect(src, isNot(contains('fontSize')));
    expect(src, contains('AppTokens.of(context)'));
    expect(src, contains('colorScheme'));
  });
}
