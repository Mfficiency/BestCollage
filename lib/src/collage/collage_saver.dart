import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

import '../services/log_service.dart';

/// Renders the collage at full resolution and stores it as a new picture.
class CollageSaver {
  CollageSaver._();

  static const String album = 'BestCollage';

  /// Captures [boundary] so its long edge is [longEdge] pixels, as PNG bytes.
  static Future<Uint8List> render(
      RenderRepaintBoundary boundary, int longEdge) async {
    final size = boundary.size;
    final ratio = longEdge / (size.longestSide == 0 ? 1 : size.longestSide);
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('could not encode the collage');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'BestCollage_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
  }

  /// Saves [png] as a new picture. On Android/iOS it goes into the gallery
  /// (album "BestCollage"); on desktop the user picks where. Returns a short
  /// description of where it went, or null if the user cancelled.
  static Future<String?> save(Uint8List png) async {
    final name = fileName(DateTime.now());
    if (Platform.isAndroid || Platform.isIOS) {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw const FileSystemException(
              'Permission to save pictures was denied');
        }
      }
      await Gal.putImageBytes(png, album: album, name: name.split('.').first);
      LogService.add('save', 'saved $name to gallery (${png.length} bytes)');
      return 'Gallery › $album';
    }

    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG image', extensions: ['png']),
      ],
    );
    if (location == null) return null; // dialog cancelled
    var path = location.path;
    if (!path.toLowerCase().endsWith('.png')) path = '$path.png';
    await File(path).writeAsBytes(png, flush: true);
    LogService.add('save', 'saved $path (${png.length} bytes)');
    return path;
  }
}
