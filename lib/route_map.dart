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

// A small, static map of a route's area with the route drawn over it
// (intent 0010). OpenStreetMap tiles behind the slice (a) route drawing.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'control.dart';
import 'route_geometry.dart';
import 'route_sketch.dart';

class RouteMap extends StatelessWidget {
  /// Same fixed width:height as the sketch, so cards keep their height
  /// while tiles load.
  static const double aspectRatio = RouteSketch.aspectRatio;

  /// OpenStreetMap standard tiles.
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Identifies the app to the tile server (OSM tile usage policy).
  static const String userAgentPackageName = 'com.nadovich.ebrevet';

  static const String attribution = '© OpenStreetMap contributors';

  /// Host of [tileUrlTemplate]; the mock server passes GETs to it through.
  static final String tileHost = Uri.parse(tileUrlTemplate).host;

  /// Closest zoom used to fit a short route; OSM serves up to 19.
  static const double maxFitZoom = 17;

  /// The one seam for tiles when no [tileProvider] is passed. Tests may
  /// replace it. Defaults to [defaultTileProvider].
  static TileProvider Function() tileProviderFactory = defaultTileProvider;

  /// Network tiles, cached in memory for the session by Flutter's image
  /// cache only (flutter_map's on-disk cache is turned off). Under
  /// `flutter test` tiles are disabled, so tests never make requests.
  static TileProvider defaultTileProvider() =>
      isFlutterTest ? NoTileProvider() : networkTileProvider();

  /// Tiles over package:http (routed through MockServer in mock mode). A
  /// failed tile becomes transparent instead of an error.
  static TileProvider networkTileProvider() => NetworkTileProvider(
        cachingProvider: const DisabledMapCachingProvider(),
        silenceExceptions: true,
      );

  /// Running under `flutter test` (it sets FLUTTER_TEST).
  static bool get isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  final List<Control> controls;

  /// Tiles for this map; [tileProviderFactory] is used when null.
  final TileProvider? tileProvider;

  const RouteMap({super.key, required this.controls, this.tileProvider});

  /// Screen-reader label; [controlCount] is the event's control count.
  static String semanticsLabel(int controlCount) =>
      'Map of the route area with $controlCount controls';

  RouteGeometry get geometry =>
      RouteGeometry.fromLatLongs(controls.map((c) => LatLong(c.lat, c.long)));

  /// [geometry]'s padded box as map bounds, same Web Mercator projection.
  static LatLngBounds boundsOf(RouteGeometry g) {
    final sw = g.paddedSouthWest, ne = g.paddedNorthEast;
    return LatLngBounds(LatLng(sw.lat, sw.long), LatLng(ne.lat, ne.long));
  }

  /// Fits the camera to [geometry]'s padded box (Web Mercator, EPSG:3857,
  /// flutter_map's default CRS).
  static CameraFit cameraFitOf(RouteGeometry geometry) => CameraFit.bounds(
        bounds: boundsOf(geometry),
        padding: EdgeInsets.zero,
        maxZoom: maxFitZoom,
      );

  /// The camera [cameraFitOf] gives for a map of [size].
  static MapCamera fittedCamera(RouteGeometry geometry, Size size) =>
      cameraFitOf(geometry)
          .fit(MapCamera.initialCamera(MapOptions()).withNonRotatedSize(size));

  @override
  Widget build(BuildContext context) {
    final geometry = this.geometry;
    // Not drawable: the slice (a) placeholder, and no tile layer.
    if (!geometry.isDrawable) return RouteSketch(controls: controls);

    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel(controls.length),
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: IgnorePointer(
            child: _TileMap(geometry: geometry, tileProvider: tileProvider),
          ),
        ),
      ),
    );
  }
}

/// The FlutterMap itself. Exists only while the route is drawable, so its
/// tile provider lives exactly as long as the TileLayer that disposes it.
class _TileMap extends StatefulWidget {
  final RouteGeometry geometry;
  final TileProvider? tileProvider;

  const _TileMap({required this.geometry, this.tileProvider});

  @override
  State<_TileMap> createState() => _TileMapState();
}

class _TileMapState extends State<_TileMap> {
  // Created once per map so rebuilds keep the loaded tiles. The TileLayer
  // disposes it.
  late final TileProvider _tileProvider =
      widget.tileProvider ?? RouteMap.tileProviderFactory();

  final MapController _controller = MapController();

  /// Size and bounds the camera was last fitted to.
  Size? _fittedSize;
  LatLngBounds? _fittedBounds;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _map(widget.geometry,
            Theme.of(context).colorScheme, constraints.biggest),
      );

  Widget _map(RouteGeometry geometry, ColorScheme scheme, Size size) {
    final fit = RouteMap.cameraFitOf(geometry);
    // flutter_map applies initialCameraFit only after the first frame, so
    // start the camera already fitted: the first frame then asks only for
    // the tiles this card shows.
    final camera = RouteMap.fittedCamera(geometry, size);
    // Initial options apply once; refit when the card is resized or shows
    // other controls.
    final bounds = RouteMap.boundsOf(geometry);
    if (_fittedSize != null &&
        (_fittedSize != size || _fittedBounds != bounds)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.fitCamera(fit);
      });
    }
    _fittedSize = size;
    _fittedBounds = bounds;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // Neutral themed background from slice (a): shows when tiles are
        // loading, failed or disabled.
        backgroundColor: scheme.surfaceContainerHighest,
        initialCenter: camera.center,
        initialZoom: camera.zoom,
        initialCameraFit: fit,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.none,
          keyboardOptions: const KeyboardOptions.disabled(),
          cursorKeyboardRotationOptions:
              CursorKeyboardRotationOptions.disabled(),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: RouteMap.tileUrlTemplate,
          userAgentPackageName: RouteMap.userAgentPackageName,
          tileProvider: _tileProvider,
          // Only the tiles in view: no ring of extra tiles.
          panBuffer: 0,
          keepBuffer: 0,
          // A failed tile stays empty (background shows through).
          errorImage: null,
        ),
        RouteOverlay(geometry: geometry),
        const MapAttributionChip(),
      ],
    );
  }
}

/// Map layer drawing the route with the shared slice (a) painter, at the
/// positions the map camera gives each point.
class RouteOverlay extends StatelessWidget {
  final RouteGeometry geometry;

  const RouteOverlay({super.key, required this.geometry});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final points = [
      for (final p in geometry.latLongs)
        camera.latLngToScreenOffset(LatLng(p.lat, p.long))
    ];
    return CustomPaint(
      painter: RouteSketchPainter.themed(
          geometry, Theme.of(context).colorScheme,
          screenPoints: points),
      child: const SizedBox.expand(),
    );
  }
}

/// "© OpenStreetMap contributors" in a small corner chip, readable over
/// any tile imagery.
class MapAttributionChip extends StatelessWidget {
  const MapAttributionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              RouteMap.attribution,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiles disabled: never makes a request and never draws a tile, so only
/// the background and the route show.
class NoTileProvider extends TileProvider {
  NoTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const _NeverImage();
}

class _NeverImage extends ImageProvider<_NeverImage> {
  const _NeverImage();

  @override
  Future<_NeverImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _NeverImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}
