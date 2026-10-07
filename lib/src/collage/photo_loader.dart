import 'dart:async';
import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../services/log_service.dart';
import 'collage_models.dart';

/// Picks photos and turns them into [PhotoItem]s: a size-capped image (so four
/// 50 MP photos don't exhaust memory), its decoded size, and the date it was
/// taken.
///
/// On Android the system Photo Picker is used, which needs no storage
/// permission at all.
class PhotoLoader {
  PhotoLoader._();

  /// Longest edge photos are decoded at. Comfortably above the largest export
  /// cell, small enough for four at once.
  static const int maxDecode = 2400;

  static final ImagePicker _picker = ImagePicker();

  /// Lets the user pick up to [max] photos. Empty when they cancel.
  ///
  /// [keep] copies each picked file somewhere lasting (the picker's files are
  /// temporary) and returns the new path; the date is read from the original.
  static Future<List<PhotoItem>> pick(
      {int max = 4, Future<String> Function(String path)? keep}) async {
    final List<XFile> files;
    try {
      files = max <= 1
          ? [if (await _picker.pickImage(source: ImageSource.gallery) case final f?) f]
          : await _picker.pickMultiImage(limit: max);
    } catch (e) {
      LogService.add('photos', 'picker failed: $e');
      rethrow;
    }
    final items = <PhotoItem>[];
    for (final f in files.take(max)) {
      final date = await readDate(File(f.path));
      final path = keep == null ? f.path : await keep(f.path);
      final item = await load(path, date: date);
      if (item != null) items.add(item);
    }
    LogService.add('photos', 'picked ${files.length}, loaded ${items.length}');
    return items;
  }

  /// Loads the photo at [path]. Its date is read from the file unless [date]
  /// is given.
  static Future<PhotoItem?> load(String path,
      {(DateTime?, DateSource)? date}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        LogService.add('photos', 'missing $path');
        return null;
      }
      final ImageProvider image = ResizeImage(
        FileImage(file),
        width: maxDecode,
        height: maxDecode,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );
      final size = await _decodedSize(image);
      final (takenAt, source) = date ?? await readDate(file);
      return PhotoItem(
        path: path,
        image: image,
        pixelSize: size,
        takenAt: takenAt,
        dateSource: source,
      );
    } catch (e) {
      LogService.add('photos', 'could not load $path: $e');
      return null;
    }
  }

  /// Size of the image as it will actually be drawn (after the platform
  /// decoder applies EXIF orientation), by resolving the same provider.
  static Future<Size> _decodedSize(ImageProvider provider) {
    final completer = Completer<Size>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      completer.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()));
      stream.removeListener(listener);
    }, onError: (e, _) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  /// When the photo was taken: EXIF first, then a date in the file name
  /// (IMG_20240501_..., PXL_20240501..., 2024-05-01 ...), then the file's
  /// modified time.
  static Future<(DateTime?, DateSource)> readDate(File file) async {
    try {
      final tags = await readExifFromBytes(await file.readAsBytes());
      for (final key in const [
        'EXIF DateTimeOriginal',
        'EXIF DateTimeDigitized',
        'Image DateTime',
      ]) {
        final d = parseExifDate(tags[key]?.printable);
        if (d != null) return (d, DateSource.exif);
      }
    } catch (_) {}
    final fromName = parseFileNameDate(file.uri.pathSegments.last);
    if (fromName != null) return (fromName, DateSource.fileName);
    try {
      return (await file.lastModified(), DateSource.fileModified);
    } catch (_) {
      return (null, DateSource.unknown);
    }
  }

  /// Parses EXIF's `yyyy:MM:dd HH:mm:ss`.
  static DateTime? parseExifDate(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'(\d{4})[:\-](\d{2})[:\-](\d{2})').firstMatch(raw);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }

  /// Finds a yyyyMMdd or yyyy-MM-dd date in a camera-style file name.
  static DateTime? parseFileNameDate(String name) {
    final m = RegExp(r'(19|20)(\d{2})[-_]?(\d{2})[-_]?(\d{2})').firstMatch(name);
    if (m == null) return null;
    final y = int.parse('${m[1]}${m[2]}');
    final mo = int.parse(m[3]!), d = int.parse(m[4]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }
}
