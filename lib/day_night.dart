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

import 'app_tokens.dart';

class DayNight extends ChangeNotifier {
  ThemeMode _mode;
  Color _color;
  DayNight({ThemeMode mode = ThemeMode.light, Color color = Colors.blue})
      : _mode = mode,
        _color = color;
  ThemeMode get mode => _mode;

  ThemeData get themeData => (_mode == ThemeMode.light) ? dayTheme : nightTheme;

  ThemeData get dayTheme => _buildTheme(Brightness.light);

  ThemeData get nightTheme => _buildTheme(Brightness.dark);

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(brightness: brightness, seedColor: _color),
    );
    final scheme = base.colorScheme;
    final tokens = AppTokens.fromScheme(scheme, base.textTheme);
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius));
    final padding = EdgeInsets.symmetric(
        horizontal: tokens.spaceLarge, vertical: tokens.spaceSmall);
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[tokens],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: shape,
          padding: padding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          shape: shape,
          padding: padding,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: shape,
        insetPadding: EdgeInsets.all(tokens.spaceMedium),
      ),
    );
  }

  Icon get icon =>
      Icon((_mode == ThemeMode.light) ? Icons.light_mode : Icons.dark_mode);
  void toggleMode() {
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  set color(Color c) {
    _color = c;
    notifyListeners();
  }

  Color get color => _color;
}
