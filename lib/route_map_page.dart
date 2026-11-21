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
// and route overlay from route_map.dart.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'control.dart';
import 'event.dart';
import 'route_geometry.dart';
import 'route_map.dart';
import 'route_sketch.dart';

class RouteMapPage extends StatefulWidget {
  final Event event;

  /// Tiles for this map; [RouteMap.tileProviderFactory] is used when null.
  final TileProvider? tileProvider;

  const RouteMapPage({super.key, required this.event, this.tileProvider});

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

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Scaffold(
      appBar: AppBar(title: Text(event.nameDist)),
      body: _geometry.isDrawable
          ? LayoutBuilder(
              builder: (context, constraints) => _RouteMapBody(
                event: event,
                geometry: _geometry,
                size: constraints.biggest,
                tileProvider: widget.tileProvider,
              ),
            )
          // Not reached from the card (its placeholder is not tappable),
          // but never show an empty map.
          : Center(child: RouteSketch(controls: event.controls)),
    );
  }
}

class _RouteMapBody extends StatefulWidget {
  final Event event;
  final RouteGeometry geometry;
  final Size size;
  final TileProvider? tileProvider;

  const _RouteMapBody(
      {required this.event,
      required this.geometry,
      required this.size,
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
    // Same fit as the card map (plus room for the labels), applied from
    // the first frame.
    const padding = RouteMapPage.markerPadding;
    final camera =
        RouteMap.fittedCamera(geometry, widget.size, padding: padding);
    final controls = RouteMapPage.usableControls(widget.event.controls);
    return FlutterMap(
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
                  onTap: () => showControlDetails(context, controls[i]),
                ),
              ),
          ],
        ),
        const MapAttributionChip(),
      ],
    );
  }

  Future<void> showControlDetails(BuildContext context, Control control) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) =>
            ControlDetailsSheet(event: widget.event, control: control),
      );
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

/// Full name, address and (for a timed control) open and close times.
class ControlDetailsSheet extends StatelessWidget {
  final Event event;
  final Control control;

  const ControlDetailsSheet(
      {super.key, required this.event, required this.control});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timed = !event.isUntimedControl(control);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(control.name, style: textTheme.titleLarge),
            if (control.address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(control.address, style: textTheme.bodyMedium),
            ],
            if (timed) ...[
              const SizedBox(height: 8),
              Text('Open: ${event.openTimeString(control.index)}',
                  style: textTheme.bodyMedium),
              Text('Close: ${event.closeTimeString(control.index)}',
                  style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
