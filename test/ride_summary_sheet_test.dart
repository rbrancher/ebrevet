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
      'Sample Hills',
      '200 km · ${event.dateTime} ${start.timeZoneName}',
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
