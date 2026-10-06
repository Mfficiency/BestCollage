import 'dart:ui' as ui;

import 'package:best_collage/best_collage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Builds an in-memory gradient photo. Everything is synchronous
/// (`toImageSync` + a [SynchronousFuture] provider), so it works inside the
/// fake-async zone of `testWidgets` without any `runAsync`.
PhotoItem testPhoto({
  Color from = Colors.orange,
  Color to = Colors.indigo,
  int width = 300,
  int height = 200,
  DateTime? takenAt,
  DateSource source = DateSource.exif,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
            rect.topLeft, rect.bottomRight, [from, to]));
  canvas.drawCircle(rect.center, height / 4,
      Paint()..color = Colors.white.withValues(alpha: 0.7));
  final image = recorder.endRecording().toImageSync(width, height);
  return PhotoItem(
    path: '',
    image: SyncImageProvider(image),
    pixelSize: Size(width.toDouble(), height.toDouble()),
    takenAt: takenAt ?? DateTime(2024, 5, 1),
    dateSource: source,
  );
}

/// Four distinct sample photos (landscape and portrait mixed).
List<PhotoItem> samplePhotos([int count = 4]) => [
      testPhoto(
          from: const Color(0xFFFF8A65),
          to: const Color(0xFF6A1B9A),
          takenAt: DateTime(2024, 5, 1)),
      testPhoto(
          from: const Color(0xFF4DD0E1),
          to: const Color(0xFF1A237E),
          width: 200,
          height: 300,
          takenAt: DateTime(2023, 12, 24)),
      testPhoto(
          from: const Color(0xFFAED581),
          to: const Color(0xFF1B5E20),
          takenAt: DateTime(2025, 8, 15)),
      testPhoto(
          from: const Color(0xFFFFF176),
          to: const Color(0xFFE65100),
          width: 240,
          height: 240,
          takenAt: DateTime(2026, 1, 2)),
    ].take(count).toList();

class SyncImageProvider extends ImageProvider<SyncImageProvider> {
  final ui.Image image;
  const SyncImageProvider(this.image);

  @override
  Future<SyncImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          SyncImageProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}
