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

// Collapsible ride summary over the full-screen map (intent 0013): a
// persistent bottom sheet with the event's key facts and its controls.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_tokens.dart';
import 'control.dart';
import 'event.dart';
import 'region.dart';
import 'route_map.dart';
import 'utility.dart';

/// Opens [uri] (a `tel:` link); returns whether it launched.
typedef PhoneLauncher = Future<bool> Function(Uri uri);

class RideSummarySheet extends StatefulWidget {
  final Event event;

  /// Drives and reports the sheet's extent; owned by the page.
  final DraggableScrollableController controller;

  /// The control shown in full and scrolled into view, if any.
  final Control? highlighted;

  /// Changed by the page to expand to [highlighted] again, e.g. when the
  /// same marker is tapped after the sheet was collapsed.
  final int revealRequest;

  /// Called when a control in the list is tapped.
  final ValueChanged<Control>? onControlTap;

  /// The event card's buttons beside its title (event info, check-ins),
  /// shown beside the sheet's title as on the card.
  final WidgetBuilder? headerActions;

  /// The event card's ride row (outcome and ride button), shown below the
  /// title as on the card.
  final WidgetBuilder? rideActions;

  const RideSummarySheet({
    super.key,
    required this.event,
    required this.controller,
    this.highlighted,
    this.revealRequest = 0,
    this.onControlTap,
    this.headerActions,
    this.rideActions,
  });

  /// Height of the collapsed sheet: handle, title (name and distance) and
  /// start.
  static const double collapsedHeight = 120;

  /// The collapsed sheet never takes more of a short body than this.
  static const double maxCollapsedSize = 0.45;

  /// The sheet opens at half height.
  static const double halfSize = 0.5;
  static const double expandedSize = 0.75;

  /// Minimum height of the drag handle's tap target, in dp.
  static const double handleTapTarget = 48;

  static const Duration animationDuration = Duration(milliseconds: 250);

  static const String expandLabel = 'Expand ride summary';
  static const String collapseLabel = 'Collapse ride summary';

  /// Key of the sheet's surface, whose height is the visible extent.
  static const Key surfaceKey = ValueKey('ride-summary-sheet');

  /// Collapsed size as a fraction of a body [height].
  static double collapsedSize(double height) => height <= 0
      ? maxCollapsedSize
      : min(collapsedHeight / height, maxCollapsedSize);

  /// Collapsed height in dp for a body [height].
  static double collapsedExtent(double height) =>
      collapsedSize(height) * height;

  /// Height in dp of the sheet as it opens (half) for a body [height].
  static double initialExtent(double height) => halfSize * height;

  /// The one seam for calling the organizer. Null where launching is not
  /// supported (web) and under `flutter test`, so tests never launch;
  /// tests may inject a fake.
  static PhoneLauncher? phoneLauncher = defaultPhoneLauncher();

  static PhoneLauncher? defaultPhoneLauncher() =>
      kIsWeb || RouteMap.isFlutterTest ? null : (uri) => launchUrl(uri);

  /// A feed value worth showing: not empty and not the "?" placeholder.
  static bool isKnown(String value) =>
      value.trim().isNotEmpty && value.trim() != '?';

  static Uri telUri(String phone) =>
      Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));

  /// Course distance of [c] in km, one decimal.
  static String controlKm(Control c) =>
      (c.distMi * 1.609344).toStringAsFixed(1);

  /// Start date and time, with the time zone name when there is a start.
  static String startText(Event event) {
    final start = event.startDateTime;
    if (start == null ||
        event.startTimeWindow.startStyle == StartStyle.permanent) {
      return event.dateTime;
    }
    return '${event.dateTime} ${start.toLocal().timeZoneName}';
  }

  /// Time from the start control opening to the finish control closing,
  /// e.g. "13h30"; null without controls.
  static String? timeLimitText(Event event) {
    if (event.controls.isEmpty) return null;
    // Same span as Event.allowedDuration, taken from the list ends.
    final d = event.controls.last.close.difference(event.controls.first.open);
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '${d.inHours}h$m';
  }

  @override
  State<RideSummarySheet> createState() => _RideSummarySheetState();
}

class _RideSummarySheetState extends State<RideSummarySheet> {
  final Map<int, GlobalKey> _rowKeys = {};
  ScrollController? _scroll;
  double _minSize = RideSummarySheet.maxCollapsedSize;
  bool _collapsed = false;
  bool _expanded = false;

  DraggableScrollableController get _sheet => widget.controller;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onExtent);
  }

  @override
  void didUpdateWidget(RideSummarySheet old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onExtent);
      widget.controller.addListener(_onExtent);
    }
    final c = widget.highlighted;
    if (c != null &&
        (!identical(c, old.highlighted) ||
            widget.revealRequest != old.revealRequest)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(c));
    }
  }

  @override
  void dispose() {
    _sheet.removeListener(_onExtent);
    super.dispose();
  }

  void _onExtent() {
    final collapsed = _sheet.size <= _minSize + 0.01;
    final expanded = _sheet.size >= RideSummarySheet.expandedSize - 0.01;
    if (collapsed != _collapsed || expanded != _expanded) {
      setState(() {
        _collapsed = collapsed;
        _expanded = expanded;
      });
    }
  }

  /// Expands to at least half and scrolls [c]'s row into view.
  Future<void> _reveal(Control c) async {
    if (!mounted) return;
    if (_sheet.isAttached && _sheet.size < RideSummarySheet.halfSize - 0.01) {
      await _sheet.animateTo(RideSummarySheet.halfSize,
          duration: RideSummarySheet.animationDuration, curve: Curves.easeOut);
    }
    if (!mounted) return;
    final row = _rowKeys[c.index]?.currentContext?.findRenderObject();
    final scroll = _scroll;
    if (row == null || !row.attached || scroll == null || !scroll.hasClients) {
      return;
    }
    // The row at the top of the list, just below the pinned handle.
    final position = scroll.position;
    final reveal = RenderAbstractViewport.of(row).getOffsetToReveal(row, 0);
    final target = (reveal.offset - RideSummarySheet.handleTapTarget)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    await position.animateTo(target,
        duration: RideSummarySheet.animationDuration, curve: Curves.easeOut);
  }

  /// Steps through the three stops: collapsed, half, expanded, then back
  /// to collapsed.
  void _toggle() {
    if (!_sheet.isAttached) return;
    if (!_expanded) {
      _sheet.animateTo(
          _collapsed
              ? RideSummarySheet.halfSize
              : RideSummarySheet.expandedSize,
          duration: RideSummarySheet.animationDuration,
          curve: Curves.easeOut);
    } else {
      final scroll = _scroll;
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
      _sheet.animateTo(_minSize,
          duration: RideSummarySheet.animationDuration, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          _minSize = RideSummarySheet.collapsedSize(constraints.maxHeight);
          return DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: RideSummarySheet.halfSize,
            minChildSize: _minSize,
            maxChildSize: RideSummarySheet.expandedSize,
            snap: true,
            snapSizes: const [RideSummarySheet.halfSize],
            snapAnimationDuration: RideSummarySheet.animationDuration,
            builder: (context, scroll) {
              _scroll = scroll;
              return _surface(context, scroll);
            },
          );
        },
      );

  Widget _surface(BuildContext context, ScrollController scroll) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final top = Radius.circular(tokens.radius * 2);
    return Material(
      key: RideSummarySheet.surfaceKey,
      color: scheme.surfaceContainerLow,
      elevation: 3,
      shadowColor: scheme.shadow,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: top)),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            PinnedHeaderSliver(child: _handle(scheme)),
            SliverPadding(
              padding: EdgeInsets.only(bottom: tokens.spaceLarge),
              sliver: SliverToBoxAdapter(child: _content(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle(ColorScheme scheme) {
    final label = _expanded
        ? RideSummarySheet.collapseLabel
        : RideSummarySheet.expandLabel;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Semantics(
        button: true,
        label: label,
        onTap: _toggle,
        excludeSemantics: true,
        child: InkWell(
          onTap: _toggle,
          child: SizedBox(
            height: RideSummarySheet.handleTapTarget,
            width: double.infinity,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox(width: 32, height: 4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final event = widget.event;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = AppTokens.of(context);
    final headerActions = widget.headerActions;
    final rideActions = widget.rideActions;

    // Section titles rank below the headline and above the body text.
    Widget section(String title) => Padding(
          padding: EdgeInsets.fromLTRB(tokens.spaceMedium, tokens.spaceSmall,
              tokens.spaceMedium, tokens.spaceSmall),
          child: Semantics(
            header: true,
            child: Text(title,
                style:
                    textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headline and subhead as on the event card, with the card's info
        // and check-ins buttons. Collapsed content: name, distance, start.
        Padding(
          padding: EdgeInsets.fromLTRB(tokens.spaceMedium, 0,
              headerActions == null ? tokens.spaceMedium : 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.nameDist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface),
                      ),
                      Text(
                        RideSummarySheet.startText(event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              if (headerActions != null) headerActions(context),
            ],
          ),
        ),
        // The card's ride row: outcome and ride button.
        if (rideActions != null) ...[
          SizedBox(height: tokens.spaceSmall),
          rideActions(context),
        ],
        SizedBox(height: tokens.spaceSmall),
        const Divider(),
        section('Ride details'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spaceMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _details(context),
          ),
        ),
        SizedBox(height: tokens.spaceSmall),
        const Divider(),
        section('${event.controls.length} controls'),
        for (var i = 0; i < event.controls.length; i++)
          KeyedSubtree(
            key: _rowKeys.putIfAbsent(event.controls[i].index, GlobalKey.new),
            child: ControlRow(
              event: event,
              control: event.controls[i],
              number: i + 1,
              highlighted: identical(event.controls[i], widget.highlighted),
              onTap: widget.onControlTap == null
                  ? null
                  : () => widget.onControlTap!(event.controls[i]),
            ),
          ),
      ],
    );
  }

  /// The "Ride details" lines.
  List<Widget> _details(BuildContext context) {
    final event = widget.event;
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final body = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurface);
    final region = Region(regionID: event.regionID);
    final kind = [
      if (RideSummarySheet.isKnown(event.eventSanction)) event.eventSanction,
      if (RideSummarySheet.isKnown(event.eventType)) event.eventType,
    ].join(' ');
    final place = [
      if (RideSummarySheet.isKnown(event.startCity)) event.startCity,
      if (RideSummarySheet.isKnown(event.startState)) event.startState,
    ].join(', ');
    final limit = RideSummarySheet.timeLimitText(event);
    final phone = event.organizerPhone;
    final launcher = RideSummarySheet.phoneLauncher;

    Widget line(String text) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(text, style: body),
        );

    return [
      if (kind.isNotEmpty) line(kind),
      if (limit != null) line('Time limit: $limit (start to finish)'),
      if (place.isNotEmpty) line('Start location: $place'),
      line('Club: ${region.clubName}'),
      line('Region: ${region.regionName}'),
      if (event.gravelDistance > 0) line('Gravel: ${event.gravelDistance} km'),
      line(event.cueVersion > 0
          ? 'Cue version: ${event.cueVersion}'
          : 'No cue sheet'),
      if (RideSummarySheet.isKnown(event.organizerName))
        line('Organizer: ${event.organizerName}'),
      if (RideSummarySheet.isKnown(phone))
        launcher == null
            ? line('Phone: $phone')
            : Semantics(
                link: true,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(RideSummarySheet.handleTapTarget,
                        RideSummarySheet.handleTapTarget),
                    padding:
                        EdgeInsets.symmetric(horizontal: tokens.spaceSmall),
                  ),
                  onPressed: () => launcher(RideSummarySheet.telUri(phone)),
                  icon: const Icon(Icons.phone),
                  label: Text(phone),
                ),
              ),
    ];
  }
}

/// One control in the summary list, a Material 3 list item: its [number]
/// in a leading badge, the name, and the distance and (if timed) open and
/// close times; in full via [ControlDetails] when highlighted.
class ControlRow extends StatelessWidget {
  final Event event;
  final Control control;

  /// Position in the route, from 1.
  final int number;
  final bool highlighted;
  final VoidCallback? onTap;

  const ControlRow({
    super.key,
    required this.event,
    required this.control,
    required this.number,
    this.highlighted = false,
    this.onTap,
  });

  /// Side of the leading number badge, in dp.
  static const double badgeSize = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = AppTokens.of(context);
    final timed = !event.isUntimedControl(control);
    final km = '${RideSummarySheet.controlKm(control)} km';
    final times = timed
        ? ' · ${Utility.toBriefDateTimeString(control.open)}'
            ' – ${Utility.toBriefDateTimeString(control.close)}'
        : '';
    final titleColor =
        highlighted ? scheme.onSecondaryContainer : scheme.onSurface;
    return Material(
      color: highlighted ? scheme.secondaryContainer : Colors.transparent,
      child: ListTile(
        selected: highlighted,
        onTap: onTap,
        leading: DecoratedBox(
          decoration: BoxDecoration(
              color: scheme.primaryContainer, shape: BoxShape.circle),
          child: SizedBox.square(
            dimension: badgeSize,
            child: Center(
              child: Text('$number',
                  style: textTheme.labelLarge
                      ?.copyWith(color: scheme.onPrimaryContainer)),
            ),
          ),
        ),
        title: Text(control.name,
            style: textTheme.bodyLarge?.copyWith(color: titleColor)),
        subtitle: highlighted
            ? ControlDetails(
                event: event,
                control: control,
                color: scheme.onSecondaryContainer)
            : Text('$km$times',
                style: tokens.numericSmall
                    .copyWith(color: scheme.onSurfaceVariant)),
      ),
    );
  }
}

/// Distance, address and (for a timed control) open and close times, in
/// [color]; the name is the list item's title.
class ControlDetails extends StatelessWidget {
  final Event event;
  final Control control;
  final Color color;

  const ControlDetails(
      {super.key,
      required this.event,
      required this.control,
      required this.color});

  static String timeString(DateTime t) =>
      t.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(color: color);
    final timed = !event.isUntimedControl(control);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${RideSummarySheet.controlKm(control)} km', style: body),
        if (control.address.isNotEmpty) Text(control.address, style: body),
        if (timed) ...[
          Text('Open: ${timeString(control.open)}', style: body),
          Text('Close: ${timeString(control.close)}', style: body),
        ],
      ],
    );
  }
}
