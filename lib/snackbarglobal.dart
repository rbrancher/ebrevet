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

import 'package:ebrevet_card/mylogger.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Styles for [AppSnack] messages.
enum AppSnackStyle {
  info(),
  success(icon: Icons.emoji_events),
  comment(icon: Icons.comment, duration: Duration(seconds: 8)),
  error(icon: Icons.error);

  final Duration duration;
  final IconData icon;

  const AppSnackStyle({
    this.duration = const Duration(seconds: 3),
    this.icon = Icons.info,
  });
}

/// Material 3 SnackBars shown through a global [ScaffoldMessenger].
/// `MaterialApp.scaffoldMessengerKey` must be set to [messengerKey].
class AppSnack {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Show [message]. Colors come from the theme's `snackBarTheme`, except
  /// [AppSnackStyle.error], which uses `error`/`onError`.
  static void show(String message, {AppSnackStyle style = AppSnackStyle.info}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) {
      MyLogger.entry('No ScaffoldMessenger; cannot show: $message');
      return;
    }
    messenger.showSnackBar(buildSnackBar(messenger.context, message, style));
  }

  static SnackBar buildSnackBar(
      BuildContext context, String message, AppSnackStyle style) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isError = style == AppSnackStyle.error;
    final foreground = isError ? scheme.onError : scheme.onInverseSurface;
    final textStyle =
        (theme.snackBarTheme.contentTextStyle ?? theme.textTheme.bodyMedium)
            ?.copyWith(color: foreground);
    final tokens = theme.extension<AppTokens>();
    return SnackBar(
      backgroundColor: isError ? scheme.error : null,
      duration: style.duration,
      content: Row(
        children: <Widget>[
          Icon(style.icon, color: foreground),
          SizedBox(width: tokens?.spaceMedium ?? 16),
          Expanded(child: Text(message, style: textStyle)),
        ],
      ),
    );
  }
}
