import 'package:flutter/material.dart';

/// Named colour looks. Each is a colour matrix applied before the sliders
/// (see color_matrix.dart). Keys are stable; labels are what the UI shows.
enum ToneFilter {
  original('Original'),
  warm('Warm'),
  cool('Cool'),
  vivid('Vivid'),
  fade('Fade'),
  vintage('Vintage'),
  sepia('Sepia'),
  mono('B&W');

  const ToneFilter(this.label);
  final String label;
}

/// One set of colour adjustments. Used twice: once for the whole collage and
/// once per photo — the photo's set is applied on top of the collage's.
///
/// Slider values are all centred on 0 so "no change" is the default.
class Adjustments {
  ToneFilter tone;

  /// Hue rotation in degrees, -180..180.
  double hue;

  /// -1 (grey) .. 1 (double saturation).
  double saturation;

  /// -1 .. 1.
  double brightness;

  /// -1 (cool / blue) .. 1 (warm / orange).
  double warmth;

  Adjustments({
    this.tone = ToneFilter.original,
    this.hue = 0,
    this.saturation = 0,
    this.brightness = 0,
    this.warmth = 0,
  });

  bool get isIdentity =>
      tone == ToneFilter.original &&
      hue == 0 &&
      saturation == 0 &&
      brightness == 0 &&
      warmth == 0;

  void reset() {
    tone = ToneFilter.original;
    hue = 0;
    saturation = 0;
    brightness = 0;
    warmth = 0;
  }

  Adjustments copy() => Adjustments(
        tone: tone,
        hue: hue,
        saturation: saturation,
        brightness: brightness,
        warmth: warmth,
      );
}

/// Where a photo's date stamp sits inside its cell, and how big it is.
///
/// [x]/[y] are 0..1 fractions of the free space in the cell (0,0 = top-left,
/// 1,1 = bottom-right), so the stamp stays put relative to the photo when a
/// divider moves. [size] is the font size as a fraction of the collage's
/// shorter side, so the saved picture looks exactly like the preview.
class DateStampPlacement {
  double x;
  double y;
  double size;

  static const double minSize = 0.02;
  static const double maxSize = 0.14;
  static const double defaultSize = 0.045;

  DateStampPlacement({this.x = 0.92, this.y = 0.94, this.size = defaultSize});

  DateStampPlacement copy() => DateStampPlacement(x: x, y: y, size: size);
}

/// Where a photo's date came from — EXIF is exact, the others are guesses.
enum DateSource { exif, fileName, fileModified, manual, unknown }

/// One photo in the collage and everything the user did to it.
class PhotoItem {
  /// Path on disk (empty for in-memory test images).
  final String path;

  /// What's drawn. Usually a size-capped [FileImage]; tests pass a MemoryImage.
  final ImageProvider image;

  /// Decoded pixel size (before [quarterTurns]). Needed to fill the cell.
  final Size pixelSize;

  DateTime? takenAt;
  DateSource dateSource;

  /// Rotation in 90° steps, clockwise. 0..3.
  int quarterTurns = 0;
  bool flipped = false;

  /// Crop: 1 = photo just fills the cell; up to [maxZoom].
  double zoom = 1;

  /// Crop position as an [Alignment] inside the cell (-1..1 each axis):
  /// which part of the (zoomed) photo is visible.
  double alignX = 0;
  double alignY = 0;

  final Adjustments adjustments = Adjustments();
  bool showDate = true;
  DateStampPlacement stamp = DateStampPlacement();

  static const double maxZoom = 6;

  PhotoItem({
    required this.path,
    required this.image,
    required this.pixelSize,
    this.takenAt,
    this.dateSource = DateSource.unknown,
  });

  /// Pixel size after rotation (width/height swap on odd quarter turns).
  Size get orientedSize => quarterTurns.isOdd
      ? Size(pixelSize.height, pixelSize.width)
      : pixelSize;

  void resetCrop() {
    zoom = 1;
    alignX = 0;
    alignY = 0;
  }
}

/// The collage layout is a binary tree: each [SplitNode] divides its area in
/// two along [axis] at [ratio] (that's a draggable divider); each [LeafNode]
/// shows one photo slot.
sealed class LayoutNode {
  const LayoutNode();

  /// Number of photo slots under this node.
  int get slotCount;

  LayoutNode clone();
}

class LeafNode extends LayoutNode {
  final int slot;
  const LeafNode(this.slot);

  @override
  int get slotCount => 1;

  @override
  LayoutNode clone() => LeafNode(slot);
}

class SplitNode extends LayoutNode {
  /// [Axis.horizontal]: side by side (a vertical divider line).
  /// [Axis.vertical]: stacked (a horizontal divider line).
  final Axis axis;

  /// Share of the space given to [first], 0..1.
  double ratio;
  final LayoutNode first;
  final LayoutNode second;

  static const double minRatio = 0.1;
  static const double maxRatio = 0.9;

  SplitNode(this.axis, this.first, this.second, {this.ratio = 0.5});

  @override
  int get slotCount => first.slotCount + second.slotCount;

  @override
  LayoutNode clone() =>
      SplitNode(axis, first.clone(), second.clone(), ratio: ratio);
}

/// A canvas shape the user can pick. [ratio] is width / height.
class CanvasShape {
  final String label;
  final double ratio;
  const CanvasShape(this.label, this.ratio);

  static const List<CanvasShape> all = [
    CanvasShape('1:1', 1),
    CanvasShape('4:5', 4 / 5),
    CanvasShape('3:4', 3 / 4),
    CanvasShape('9:16', 9 / 16),
    CanvasShape('3:2', 3 / 2),
    CanvasShape('16:9', 16 / 9),
  ];
}

/// Colours offered for the date stamp. The first is the classic film-camera
/// orange.
const List<Color> dateStampColors = [
  Color(0xFFFF8A1F),
  Color(0xFFFFD54F),
  Color(0xFFFFFFFF),
  Color(0xFFE53935),
  Color(0xFF000000),
];

/// Colours offered for the border between photos.
const List<Color> borderColors = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFF5EBDD),
  Color(0xFF9E9E9E),
  Color(0xFF005FDD),
  Color(0xFFE91E63),
];

/// dd.mm.yy — the format the date stamp always uses.
String formatStampDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${two(d.year % 100)}';
}
