// Copyright (C) 2026 eBrevet autonomous AI-SDLC
// This file is part of eBrevet <https://github.com/ctnadovich/ebrevet>.
//
// eBrevet is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// eBrevet is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with eBrevet.  If not, see <http://www.gnu.org/licenses/>.
//

import 'package:flutter/material.dart';

/// A status color and the color to draw text or icons on top of it.
@immutable
class StatusColors {
  final Color color;
  final Color onColor;
  const StatusColors(this.color, this.onColor);

  static StatusColors lerp(StatusColors a, StatusColors b, double t) =>
      StatusColors(Color.lerp(a.color, b.color, t)!,
          Color.lerp(a.onColor, b.onColor, t)!);

  @override
  bool operator ==(Object other) =>
      other is StatusColors && other.color == color && other.onColor == onColor;

  @override
  int get hashCode => Object.hash(color, onColor);
}

/// App-wide design tokens: spacing, shape, status colors and a numeric
/// text style. Registered on the theme in `day_night.dart`; read with
/// `AppTokens.of(context)`.
///
/// This is the only file (with `day_night.dart`) allowed to hold fixed
/// color values; see `test/style_guardrail_test.dart`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Fixed source hues for custom status colors (M3 custom-color pattern).
  static const Color onTimeSource = Color(0xFF2E7D32); // green
  static const Color closingSoonSource = Color(0xFFFFB300); // amber
  static const Color pendingSource = Color(0xFFF57C00); // orange

  /// Default theme seed: the value of Material `Colors.blue`, so the default
  /// look and any saved theme color are unchanged.
  static const Color defaultSeed = Color(0xFF2196F3);

  /// Minimum contrast of an icon-only status color against `surface`
  /// (WCAG non-text contrast).
  static const double minIconContrast = 3;

  final double spaceSmall;
  final double spaceMedium;
  final double spaceLarge;
  final double radius;

  final StatusColors onTime;
  final StatusColors closingSoon;
  final StatusColors closed;
  final StatusColors checkedIn;
  final StatusColors dnf;

  /// A check-in recorded on the device but not yet posted to the server.
  /// `pending.color` is drawn as an icon on the card surface.
  final StatusColors pending;

  /// Style for times, distances and codes, with tabular (fixed-width) digits.
  final TextStyle numeric;

  /// Smaller [numeric] for card detail lines.
  final TextStyle numericSmall;

  const AppTokens({
    this.spaceSmall = 8,
    this.spaceMedium = 16,
    this.spaceLarge = 24,
    this.radius = 12,
    required this.onTime,
    required this.closingSoon,
    required this.closed,
    required this.checkedIn,
    required this.dnf,
    required this.pending,
    required this.numeric,
    required this.numericSmall,
  });

  /// Minimum contrast for every status pair (WCAG AA for normal text).
  static const double minContrast = 4.5;

  /// Builds tokens for [scheme] (whose brightness selects light or dark
  /// status pairs) and [textTheme].
  factory AppTokens.fromScheme(ColorScheme scheme, TextTheme textTheme) {
    StatusColors custom(Color source) {
      final s = ColorScheme.fromSeed(
          seedColor: source, brightness: scheme.brightness);
      return StatusColors(s.primaryContainer, s.onPrimaryContainer);
    }

    // Pending is shown as a bare icon, so it uses the orange scheme's
    // primary (icon-strength against surface) rather than its container.
    final orange = ColorScheme.fromSeed(
        seedColor: pendingSource, brightness: scheme.brightness);

    // ThemeData.textTheme holds colors only; Theme.of() merges in the M3
    // sizes later, but extensions are not localized. Copy the M3 size so
    // numeric and numericSmall have real, ordered sizes.
    TextStyle tabular(TextStyle? role, TextStyle? geometry) =>
        (role ?? const TextStyle()).copyWith(
          fontSize: geometry?.fontSize,
          height: geometry?.height,
          letterSpacing: geometry?.letterSpacing,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    const geometry = Typography.englishLike2021;

    return AppTokens(
      onTime: custom(onTimeSource),
      closingSoon: custom(closingSoonSource),
      closed: StatusColors(scheme.error, scheme.onError),
      checkedIn: StatusColors(scheme.primary, scheme.onPrimary),
      dnf: StatusColors(scheme.surface, scheme.onSurfaceVariant),
      pending: StatusColors(orange.primary, orange.onPrimary),
      numeric: tabular(textTheme.titleLarge, geometry.titleLarge),
      numericSmall: tabular(textTheme.bodyMedium, geometry.bodyMedium),
    );
  }

  /// WCAG 2 contrast ratio between two opaque colors.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Tokens from the ambient theme.
  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({
    double? spaceSmall,
    double? spaceMedium,
    double? spaceLarge,
    double? radius,
    StatusColors? onTime,
    StatusColors? closingSoon,
    StatusColors? closed,
    StatusColors? checkedIn,
    StatusColors? dnf,
    StatusColors? pending,
    TextStyle? numeric,
    TextStyle? numericSmall,
  }) =>
      AppTokens(
        spaceSmall: spaceSmall ?? this.spaceSmall,
        spaceMedium: spaceMedium ?? this.spaceMedium,
        spaceLarge: spaceLarge ?? this.spaceLarge,
        radius: radius ?? this.radius,
        onTime: onTime ?? this.onTime,
        closingSoon: closingSoon ?? this.closingSoon,
        closed: closed ?? this.closed,
        checkedIn: checkedIn ?? this.checkedIn,
        dnf: dnf ?? this.dnf,
        pending: pending ?? this.pending,
        numeric: numeric ?? this.numeric,
        numericSmall: numericSmall ?? this.numericSmall,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    double d(double a, double b) => a + (b - a) * t;
    return AppTokens(
      spaceSmall: d(spaceSmall, other.spaceSmall),
      spaceMedium: d(spaceMedium, other.spaceMedium),
      spaceLarge: d(spaceLarge, other.spaceLarge),
      radius: d(radius, other.radius),
      onTime: StatusColors.lerp(onTime, other.onTime, t),
      closingSoon: StatusColors.lerp(closingSoon, other.closingSoon, t),
      closed: StatusColors.lerp(closed, other.closed, t),
      checkedIn: StatusColors.lerp(checkedIn, other.checkedIn, t),
      dnf: StatusColors.lerp(dnf, other.dnf, t),
      pending: StatusColors.lerp(pending, other.pending, t),
      numeric: TextStyle.lerp(numeric, other.numeric, t)!,
      numericSmall: TextStyle.lerp(numericSmall, other.numericSmall, t)!,
    );
  }
}
