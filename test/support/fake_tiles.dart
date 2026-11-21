// Fake map tiles for tests (intent 0010): never touch the network.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// 1x1 transparent PNG.
final Uint8List transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Records every tile asked for. Serves a transparent tile, or fails every
/// tile when [fail] is set (offline).
class FakeTileProvider extends TileProvider {
  final bool fail;
  final List<TileCoordinates> requested = [];

  FakeTileProvider({this.fail = false});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requested.add(coordinates);
    if (fail) return const FailingImage();
    return MemoryImage(transparentPng);
  }
}

/// An image that always fails to load, like a tile with no signal.
class FailingImage extends ImageProvider<FailingImage> {
  const FailingImage();

  @override
  Future<FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          FailingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          Future<ImageInfo>.error(StateError('offline: no tile')));
}
