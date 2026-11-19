// AppSnack replaces the retired Flushbar overlay (intent 0004).

import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/mylogger.dart';
import 'package:ebrevet_card/snackbarglobal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(ThemeMode mode) {
  final dn = DayNight(mode: mode);
  return MaterialApp(
    scaffoldMessengerKey: AppSnack.messengerKey,
    theme: dn.dayTheme,
    darkTheme: dn.nightTheme,
    themeMode: mode,
    home: const Scaffold(body: SizedBox()),
  );
}

ColorScheme schemeFor(ThemeMode mode) {
  final dn = DayNight(mode: mode);
  return (mode == ThemeMode.light ? dn.dayTheme : dn.nightTheme).colorScheme;
}

/// Lets the current SnackBar time out so the next test starts clean.
Future<void> dismiss(WidgetTester tester) async {
  AppSnack.messengerKey.currentState?.clearSnackBars();
  await tester.pumpAndSettle();
}

/// Plays the role of non-widget code such as `report.dart`: no BuildContext.
void notifyFromLogic(String message, AppSnackStyle style) =>
    AppSnack.show(message, style: style);

void main() {
  // AC5 (intent 0004): every style, light and dark, no BuildContext passed.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final style in AppSnackStyle.values) {
      testWidgets('AppSnack ${style.name} shows a SnackBar (${mode.name})',
          (tester) async {
        await tester.pumpWidget(app(mode));
        final message = 'Message ${style.name} ${mode.name}';
        AppSnack.show(message, style: style);
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        final snack = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snack.duration, style.duration);
        expect(find.byIcon(style.icon), findsOneWidget);

        final scheme = schemeFor(mode);
        final textColor = tester
            .renderObject<RenderParagraph>(find.text(message))
            .text
            .style
            ?.color;
        final iconColor = tester.widget<Icon>(find.byIcon(style.icon)).color;
        if (style == AppSnackStyle.error) {
          expect(snack.backgroundColor, scheme.error);
          expect(textColor, scheme.onError);
          expect(iconColor, scheme.onError);
        } else {
          // Colors come from the theme's snackBarTheme.
          expect(snack.backgroundColor, isNull);
          expect(textColor, scheme.onInverseSurface);
          expect(iconColor, scheme.onInverseSurface);
        }
        await dismiss(tester);
      });
    }
  }

  // AC5 (intent 0004)
  testWidgets('AppSnack before any ScaffoldMessenger logs, does not throw',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(AppSnack.messengerKey.currentState, isNull);
    expect(() => AppSnack.show('Startup message', style: AppSnackStyle.error),
        returnsNormally);
    expect(MyLogger.records.any((r) => r.contains('Startup message')), isTrue);
  });

  // AC6 (intent 0004): messages raised from non-widget code still appear.
  testWidgets('AppSnack from outside any widget shows the message',
      (tester) async {
    await tester.pumpWidget(app(ThemeMode.light));
    notifyFromLogic('Current checkin status uploaded.', AppSnackStyle.info);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Current checkin status uploaded.'), findsOneWidget);
    await dismiss(tester);
  });
}
