import 'dart:math' as math;

import 'package:ebrevet_card/app_tokens.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Independent of AppTokens.contrastRatio so the check does not test itself.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Map<String, StatusColors> pairs(AppTokens t) => {
      'onTime': t.onTime,
      'closingSoon': t.closingSoon,
      'closed': t.closed,
      'checkedIn': t.checkedIn,
      'dnf': t.dnf,
    };

AppTokens tokensOf(ThemeData theme) => theme.extension<AppTokens>()!;

/// Host app mirroring MyApp's theme wiring, without the event pages.
Widget host(DayNight dayNight, void Function(BuildContext) probe) =>
    ChangeNotifierProvider.value(
      value: dayNight,
      child: Consumer<DayNight>(
        builder: (context, dn, _) => MaterialApp(
          theme: dn.dayTheme,
          darkTheme: dn.nightTheme,
          themeMode: dn.mode,
          home: Builder(builder: (context) {
            probe(context);
            return const SizedBox();
          }),
        ),
      ),
    );

void main() {
  // Default seed plus a spread of hues a region might choose.
  const seeds = <Color>[
    Colors.blue, // DayNight default
    Colors.red,
    Colors.green,
    Colors.amber,
    Colors.purple,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];

  // AC1 (intent 0001)
  test('AppTokens exposes spacing, radius and status pairs', () {
    final t = tokensOf(DayNight().dayTheme);
    expect(t, isA<ThemeExtension<AppTokens>>());
    expect(t.spaceSmall, greaterThan(0));
    expect(t.spaceMedium, greaterThan(t.spaceSmall));
    expect(t.spaceLarge, greaterThan(t.spaceMedium));
    expect(t.radius, greaterThan(0));
    for (final p in pairs(t).values) {
      expect(p.color, isNot(p.onColor));
    }
    // copyWith / lerp are well-behaved.
    expect(t.copyWith(radius: 3).radius, 3);
    expect(t.lerp(t.copyWith(spaceSmall: 10), 0.5).spaceSmall,
        (t.spaceSmall + 10) / 2);
  });

  // AC2 (intent 0001)
  group('status colors follow the M3 custom-color pattern', () {
    for (final brightness in Brightness.values) {
      test('roles map correctly ($brightness)', () {
        final dn = DayNight(color: Colors.blue);
        final theme =
            brightness == Brightness.light ? dn.dayTheme : dn.nightTheme;
        final s = theme.colorScheme;
        final t = tokensOf(theme);
        final green = ColorScheme.fromSeed(
            seedColor: AppTokens.onTimeSource, brightness: brightness);
        final amber = ColorScheme.fromSeed(
            seedColor: AppTokens.closingSoonSource, brightness: brightness);
        expect(t.onTime,
            StatusColors(green.primaryContainer, green.onPrimaryContainer));
        expect(t.closingSoon,
            StatusColors(amber.primaryContainer, amber.onPrimaryContainer));
        expect(t.closed, StatusColors(s.error, s.onError));
        expect(t.checkedIn, StatusColors(s.primary, s.onPrimary));
        expect(t.dnf, StatusColors(s.surface, s.onSurfaceVariant));
      });

      for (final seed in seeds) {
        test('every pair has >= 4.5:1 contrast ($brightness, $seed)', () {
          final dn = DayNight(color: seed);
          final theme =
              brightness == Brightness.light ? dn.dayTheme : dn.nightTheme;
          pairs(tokensOf(theme)).forEach((name, p) {
            expect(contrast(p.color, p.onColor), greaterThanOrEqualTo(4.5),
                reason: '$name in $brightness with seed $seed');
          });
        });
      }
    }
  });

  // AC3 (intent 0001)
  test('day and night themes register AppTokens', () {
    final dn = DayNight();
    expect(dn.dayTheme.extension<AppTokens>(), isNotNull);
    expect(dn.nightTheme.extension<AppTokens>(), isNotNull);
  });

  // AC3 + AC4 (intent 0001)
  testWidgets('tokens are reachable in the app in both modes and toggleMode '
      'switches day and night', (tester) async {
    final dn = DayNight();
    AppTokens? tokens;
    Brightness? brightness;
    await tester.pumpWidget(host(dn, (context) {
      tokens = Theme.of(context).extension<AppTokens>();
      brightness = Theme.of(context).brightness;
    }));
    expect(tokens, isNotNull);
    expect(brightness, Brightness.light);
    expect(tokens!.checkedIn.color, dn.dayTheme.colorScheme.primary);

    dn.toggleMode();
    await tester.pumpAndSettle();
    expect(dn.mode, ThemeMode.dark);
    expect(brightness, Brightness.dark);
    expect(tokens, isNotNull);
    expect(tokens!.checkedIn.color, dn.nightTheme.colorScheme.primary);

    dn.toggleMode();
    await tester.pumpAndSettle();
    expect(dn.mode, ThemeMode.light);
    expect(brightness, Brightness.light);
  });

  // AC4 (intent 0001)
  testWidgets('changing the seed color rebuilds themes and tokens',
      (tester) async {
    final dn = DayNight();
    AppTokens? tokens;
    await tester.pumpWidget(host(dn, (context) {
      tokens = AppTokens.of(context);
    }));
    final before = tokens!.checkedIn.color;

    dn.color = Colors.red;
    await tester.pumpAndSettle();
    expect(dn.color, Colors.red);
    final expected =
        ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.light);
    expect(dn.dayTheme.colorScheme.primary, expected.primary);
    expect(tokens!.checkedIn.color, expected.primary);
    expect(tokens!.checkedIn.color, isNot(before));
  });

  // AC5 (intent 0001)
  group('component themes use tokens and color roles', () {
    for (final brightness in Brightness.values) {
      test('$brightness', () {
        final dn = DayNight();
        final theme =
            brightness == Brightness.light ? dn.dayTheme : dn.nightTheme;
        final s = theme.colorScheme;
        final t = tokensOf(theme);
        const none = <WidgetState>{};
        final shape = RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius));

        final filled = theme.filledButtonTheme.style!;
        // AC9 (intent 0003): no color override, so FilledButton.tonal keeps
        // its M3 secondaryContainer fill (see controls_screen_test.dart).
        expect(filled.backgroundColor, isNull);
        expect(filled.foregroundColor, isNull);
        expect(filled.shape!.resolve(none), shape);

        final outlined = theme.outlinedButtonTheme.style!;
        expect(outlined.foregroundColor!.resolve(none), s.primary);
        expect(outlined.side!.resolve(none)!.color, s.outline);
        expect(outlined.shape!.resolve(none), shape);

        final snack = theme.snackBarTheme;
        expect(snack.backgroundColor, s.inverseSurface);
        expect(snack.contentTextStyle!.color, s.onInverseSurface);
        expect(snack.actionTextColor, s.inversePrimary);
        expect(snack.shape, shape);
      });
    }
  });

  // AC8 (intent 0001)
  for (final brightness in Brightness.values) {
    test('numeric style uses tabular figures ($brightness)', () {
      final dn = DayNight();
      final theme =
          brightness == Brightness.light ? dn.dayTheme : dn.nightTheme;
      final numeric = tokensOf(theme).numeric;
      expect(numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
      // Intent 0005: compare with the localized titleLarge (what
      // Theme.of(context) returns); the raw ThemeData style has no size.
      final localized =
          ThemeData.localize(theme, Typography.englishLike2021).textTheme;
      expect(numeric.fontSize, isNotNull);
      expect(numeric.fontSize, localized.titleLarge!.fontSize);
      expect(numeric.color, theme.textTheme.titleLarge!.color);
    });
  }
}
