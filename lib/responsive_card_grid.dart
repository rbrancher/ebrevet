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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// A full-width [header] above a responsive grid of [cards] (intent 0012).
///
/// The column count comes from the available width and [maxCardWidth]
/// (see [columnsFor]), not from per-device breakpoints. For reference, the
/// Material 3 window size classes are:
///
/// | Class       | Window width (dp) | Columns (with 16 dp page margins) |
/// |-------------|-------------------|-----------------------------------|
/// | compact     | under 600         | 1                                 |
/// | medium      | 600 - 839         | 1 up to 632 dp, then 2            |
/// | expanded    | 840 - 1199        | 2                                 |
/// | large       | 1200 - 1599       | 2, then 3 above 1248 dp           |
/// | extra-large | 1600 and up       | 3, in a centred [maxBodyWidth]    |
///
/// Cards are laid out in lazy rows of equal-width cards, so off-screen rows
/// are not built. When a row holds more than one card, every card in it is
/// stretched to the height of the tallest one, so rows have no dents. No
/// card has a fixed height: each row is as tall as its tallest content.
class ResponsiveCardGrid extends StatelessWidget {
  /// No card is wider than this. Chosen so that a phone (under 600 dp)
  /// always gets one column and two columns start at medium widths.
  static const double maxCardWidth = 600;

  /// The header and grid never get wider than this; on wider windows they
  /// are centred. The start of the M3 extra-large class.
  static const double maxBodyWidth = 1600;

  /// Key of the box that holds the header, for tests.
  static const Key headerKey = ValueKey('responsive-card-grid-header');

  final Widget? header;
  final List<Widget> cards;

  const ResponsiveCardGrid({super.key, this.header, required this.cards});

  /// Columns for a grid [width] wide with [gutter] between columns: the
  /// fewest columns that keep every card at most [maxCardWidth] wide.
  static int columnsFor(double width, {double gutter = 16}) {
    if (!width.isFinite || width <= maxCardWidth) return 1;
    return math.max(1, ((width + gutter) / (maxCardWidth + gutter)).ceil());
  }

  @override
  Widget build(BuildContext context) {
    final gap = AppTokens.of(context).spaceMedium;

    Widget body(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxBodyWidth),
            child: child,
          ),
        );

    return CustomScrollView(
      slivers: [
        if (header != null)
          SliverToBoxAdapter(
            child: body(Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: SizedBox(
                key: headerKey,
                width: double.infinity,
                child: header,
              ),
            )),
          ),
        SliverLayoutBuilder(builder: (context, constraints) {
          final width =
              math.min(constraints.crossAxisExtent, maxBodyWidth).toDouble();
          final columns = columnsFor(width, gutter: gap);
          final rows = (cards.length + columns - 1) ~/ columns;
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, row) {
                final first = row * columns;
                final cells = Row(
                  // Several cards per row: all as tall as the tallest one.
                  crossAxisAlignment: columns > 1
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) SizedBox(width: gap),
                      Expanded(
                        child: first + c < cards.length
                            ? cards[first + c]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                );
                return body(Padding(
                  padding: EdgeInsets.only(top: row == 0 ? 0 : gap),
                  child: columns > 1 ? IntrinsicHeight(child: cells) : cells,
                ));
              },
              childCount: rows,
            ),
          );
        }),
      ],
    );
  }
}
