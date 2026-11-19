// Copyright (C) 2023 Chris Nadovich
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

  final double spaceSmall;
  final double spaceMedium;
  final double spaceLarge;
  final double radius;

  final StatusColors onTime;
  final StatusColors closingSoon;
  final StatusColors closed;
  final StatusColors checkedIn;
  final StatusColors dnf;

  /// Style for times, distances and codes, with tabular (fixed-width) digits.
  final TextStyle numeric;

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
    required this.numeric,
  });

  /// Minimum contrast for every status pair (WCAG AA for normal text).
  static const double minContrast = 4.5;

  /// Builds tokens for [scheme] (whose brightness selects light or dark
  /// status pairs) and [textTheme].
  factory AppTokens.fromScheme(ColorScheme scheme, TextTheme textTheme) {
    StatusColors custom(Color source) {
      final s =
          ColorScheme.fromSeed(seedColor: source, brightness: scheme.brightness);
      return StatusColors(s.primaryContainer, s.onPrimaryContainer);
    }

    return AppTokens(
      onTime: custom(onTimeSource),
      closingSoon: custom(closingSoonSource),
      closed: StatusColors(scheme.error, scheme.onError),
      checkedIn: StatusColors(scheme.primary, scheme.onPrimary),
      dnf: StatusColors(scheme.surface, scheme.onSurfaceVariant),
      numeric: (textTheme.titleLarge ?? const TextStyle()).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()]),
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
    TextStyle? numeric,
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
        numeric: numeric ?? this.numeric,
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
      numeric: TextStyle.lerp(numeric, other.numeric, t)!,
    );
  }
}
