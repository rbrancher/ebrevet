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

// Full-screen, pannable and zoomable map of an event's route with named
// control markers (intent 0011). Reuses the card map's tiles, attribution
// and route overlay from route_map.dart. A collapsible ride summary sheet
// (intent 0013, ride_summary_sheet.dart) lies over the bottom of the map.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'control.dart';
import 'event.dart';
import 'ride_summary_sheet.dart';
import 'route_geometry.dart';
import 'route_map.dart';
import 'route_sketch.dart';

class RouteMapPage extends StatefulWidget {
  final Event event;

  /// Tiles for this map; [RouteMap.tileProviderFactory] is used when null.
  final TileProvider? tileProvider;

  /// The event card's buttons and ride row, shown in the summary sheet as
  /// on the card (see [RideSummarySheet.headerActions] and
  /// [RideSummarySheet.rideActions]).
  final WidgetBuilder? headerActions;
  final WidgetBuilder? rideActions;

  const RouteMapPage(
      {super.key,
      required this.event,
      this.tileProvider,
      this.headerActions,
      this.rideActions});

  /// Pan and zoom (drag, pinch, scroll, double tap, fling); no rotation.
  static const int interactionFlags =
      InteractiveFlag.all & ~InteractiveFlag.rotate;

  /// Minimum side of a control marker's tap target, in dp.
  static const double markerTapTarget = 48;

  /// Widest a marker label gets; longer names are truncated on the map.
  static const double markerMaxWidth = 120;

  /// Screen space kept free around the card map's fit so the labels of the
  /// outermost controls start fully in view.
  static const EdgeInsets markerPadding = EdgeInsets.symmetric(
      horizontal: markerMaxWidth / 2, vertical: markerTapTarget);

  /// Zoom the map is raised to, at least, when a control in the summary
  /// sheet is tapped (intent 0013).
  static const double minFocusZoom = 12;

  /// [markerPadding] plus the summary sheet's opening height
  /// ([bottomInset]) at the bottom, so the route is fitted to the area
  /// above the sheet (intent 0013).
  static EdgeInsets fitPadding(double bottomInset) =>
      markerPadding + EdgeInsets.only(bottom: bottomInset);

  /// Controls that can be placed on the map, in control order.
  static List<Control> usableControls(List<Control> controls) => [
        for (final c in controls)
          if (RouteGeometry.isUsable(LatLong(c.lat, c.long))) c
      ];

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  late final RouteGeometry _geometry = RouteGeometry.fromLatLongs(
      widget.event.controls.map((c) => LatLong(c.lat, c.long)));

  final MapController _map = MapController();
  final DraggableScrollableController _sheet = DraggableScrollableController();

  /// The control highlighted in the summary sheet (intent 0013).
  Control? _highlighted;

  /// Bumped on every marker tap so the sheet expands even when the same
  /// control is tapped again.
  int _revealRequest = 0;

  @override
  void dispose() {
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  /// A marker tap highlights its control in the sheet, which expands and
  /// scrolls to it; no modal sheet is pushed.
  void _onMarkerTap(Control c) => setState(() {
        _highlighted = c;
        _revealRequest++;
      });

  /// A tap on a control in the sheet's list highlights it and centres the
  /// map on it, in the part of the map above the sheet.
  void _onRowTap(Control c) {
    setState(() => _highlighted = c);
    if (!_geometry.isDrawable ||
        !RouteGeometry.isUsable(LatLong(c.lat, c.long))) {
      return;
    }
    final sheetHeight = _sheet.isAttached ? _sheet.pixels : 0.0;
    _map.move(
        LatLng(c.lat, c.long), max(_map.camera.zoom, RouteMapPage.minFocusZoom),
        offset: Offset(0, -sheetHeight / 2));
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Scaffold(
      appBar: AppBar(title: Text(event.nameDist)),
      body: LayoutBuilder(builder: (context, constraints) {
        final opening = RideSummarySheet.initialExtent(constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_geometry.isDrawable)
              _RouteMapBody(
                event: event,
                geometry: _geometry,
                size: constraints.biggest,
                bottomInset: opening,
                sheet: _sheet,
                controller: _map,
                onMarkerTap: _onMarkerTap,
                tileProvider: widget.tileProvider,
              )
            else
              // Not reached from the card (its placeholder is not tappable),
              // but never show an empty map.
              Padding(
                padding: EdgeInsets.only(
                    bottom: RideSummarySheet.collapsedExtent(
                        constraints.maxHeight)),
                child: Center(child: RouteSketch(controls: event.controls)),
              ),
            RideSummarySheet(
              event: event,
              controller: _sheet,
              highlighted: _highlighted,
              revealRequest: _revealRequest,
              onControlTap: _onRowTap,
              headerActions: widget.headerActions,
              rideActions: widget.rideActions,
            ),
          ],
        );
      }),
    );
  }
}

class _RouteMapBody extends StatefulWidget {
  final Event event;
  final RouteGeometry geometry;
  final Size size;

  /// Height of the summary sheet over the bottom of the map as it opens.
  final double bottomInset;

  /// The summary sheet, followed by the attribution chip.
  final DraggableScrollableController sheet;
  final MapController controller;
  final ValueChanged<Control> onMarkerTap;
  final TileProvider? tileProvider;

  const _RouteMapBody(
      {required this.event,
      required this.geometry,
      required this.size,
      required this.bottomInset,
      required this.sheet,
      required this.controller,
      required this.onMarkerTap,
      this.tileProvider});

  @override
  State<_RouteMapBody> createState() => _RouteMapBodyState();
}

class _RouteMapBodyState extends State<_RouteMapBody> {
  // Created once so rebuilds (e.g. rotation) keep the loaded tiles. The
  // TileLayer disposes it.
  late final TileProvider _tileProvider =
      widget.tileProvider ?? RouteMap.tileProviderFactory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final geometry = widget.geometry;
    // Same fit as the card map (plus room for the labels), in the area
    // above the sheet as it opens, applied from the first frame.
    final padding = RouteMapPage.fitPadding(widget.bottomInset);
    final camera =
        RouteMap.fittedCamera(geometry, widget.size, padding: padding);
    final controls = RouteMapPage.usableControls(widget.event.controls);
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        backgroundColor: scheme.surfaceContainerHighest,
        initialCenter: camera.center,
        initialZoom:
            camera.zoom.clamp(RouteMap.minZoom, RouteMap.maxZoom).toDouble(),
        initialCameraFit: RouteMap.cameraFitOf(geometry, padding: padding),
        minZoom: RouteMap.minZoom,
        maxZoom: RouteMap.maxZoom,
        interactionOptions:
            const InteractionOptions(flags: RouteMapPage.interactionFlags),
      ),
      children: [
        // Visible tiles only; already loaded tiles are kept while panning.
        RouteMap.tileLayer(_tileProvider, keepBuffer: 2),
        RouteOverlay(geometry: geometry),
        MarkerLayer(
          markers: [
            for (var i = 0; i < controls.length; i++)
              Marker(
                point: LatLng(controls[i].lat, controls[i].long),
                width: RouteMapPage.markerMaxWidth,
                height: RouteMapPage.markerTapTarget,
                // Label just above the point; on a loop the finish label
                // goes below so it does not cover the start label.
                alignment: geometry.isLoop && i == controls.length - 1
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: ControlMarker(
                  control: controls[i],
                  onTap: () => widget.onMarkerTap(controls[i]),
                ),
              ),
          ],
        ),
        // Follows the top of the sheet so it is never hidden.
        ListenableBuilder(
          listenable: widget.sheet,
          builder: (context, child) => Padding(
            padding: EdgeInsets.only(
                bottom: widget.sheet.isAttached
                    ? widget.sheet.pixels
                    : widget.bottomInset),
            child: child,
          ),
          child: const MapAttributionChip(),
        ),
      ],
    );
  }
}

/// A control's name in a small chip, with a tap target of at least
/// [RouteMapPage.markerTapTarget] on each side.
class ControlMarker extends StatelessWidget {
  final Control control;
  final VoidCallback onTap;

  const ControlMarker({super.key, required this.control, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Semantics(
        button: true,
        label: control.name,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: RouteMapPage.markerTapTarget,
              minHeight: RouteMapPage.markerTapTarget,
              maxWidth: RouteMapPage.markerMaxWidth,
            ),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    control.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
