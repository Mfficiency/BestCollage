import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'collage_models.dart';

/// Colour maths for the Color tool. Everything is a 5x4 colour matrix (the
/// shape [ColorFilter.matrix] takes: rows R, G, B, A; columns R, G, B, A,
/// offset — offsets on the 0..255 scale). Matrices are combined by
/// multiplication so a photo needs exactly one [ColorFilter], however many
/// adjustments are stacked.
class ColorMatrix {
  ColorMatrix._();

  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Rec. 709 luminance weights.
  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  /// `after ∘ before`: the result applies [before] first, then [after].
  static List<double> multiply(List<double> after, List<double> before) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += after[r * 5 + k] * before[k * 5 + c];
        }
        if (c == 4) v += after[r * 5 + 4];
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  static List<double> saturation(double amount) {
    final s = 1 + amount; // 0 = grey, 1 = unchanged, 2 = double
    final r = (1 - s) * _lr, g = (1 - s) * _lg, b = (1 - s) * _lb;
    return [
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0,
      r, g, b + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// Luminance-preserving hue rotation by [degrees].
  static List<double> hue(double degrees) {
    final a = degrees * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    return [
      _lr + c * (1 - _lr) - s * _lr,
      _lg - c * _lg - s * _lg,
      _lb - c * _lb + s * (1 - _lb),
      0,
      0,
      _lr - c * _lr + s * 0.143,
      _lg + c * (1 - _lg) + s * 0.140,
      _lb - c * _lb - s * 0.283,
      0,
      0,
      _lr - c * _lr - s * (1 - _lr),
      _lg - c * _lg + s * _lg,
      _lb + c * (1 - _lb) + s * _lb,
      0,
      0,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> brightness(double amount) {
    final o = amount * 90;
    return [
      1, 0, 0, 0, o, //
      0, 1, 0, 0, o,
      0, 0, 1, 0, o,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> contrast(double factor) {
    final o = 128 * (1 - factor);
    return [
      factor, 0, 0, 0, o, //
      0, factor, 0, 0, o,
      0, 0, factor, 0, o,
      0, 0, 0, 1, 0,
    ];
  }

  /// Positive = warmer (more red/yellow), negative = cooler (more blue).
  static List<double> warmth(double amount) {
    final o = amount * 28;
    return [
      1 + amount * 0.08, 0, 0, 0, o, //
      0, 1, 0, 0, o * 0.3,
      0, 0, 1 - amount * 0.08, 0, -o,
      0, 0, 0, 1, 0,
    ];
  }

  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static List<double> tone(ToneFilter t) => switch (t) {
        ToneFilter.original => identity,
        ToneFilter.warm => warmth(0.6),
        ToneFilter.cool => warmth(-0.6),
        ToneFilter.vivid =>
          multiply(contrast(1.12), saturation(0.45)),
        ToneFilter.fade => multiply(
            brightness(0.12), multiply(contrast(0.8), saturation(-0.25))),
        ToneFilter.vintage => multiply(
            warmth(0.45),
            multiply(contrast(0.88), saturation(-0.35)),
          ),
        ToneFilter.sepia => _sepia,
        ToneFilter.mono => multiply(contrast(1.1), saturation(-1)),
      };

  /// One matrix for a whole [Adjustments] set: tone first, then the sliders.
  static List<double> forAdjustments(Adjustments a) {
    var m = tone(a.tone);
    if (a.hue != 0) m = multiply(hue(a.hue), m);
    if (a.saturation != 0) m = multiply(saturation(a.saturation), m);
    if (a.warmth != 0) m = multiply(warmth(a.warmth), m);
    if (a.brightness != 0) m = multiply(brightness(a.brightness), m);
    return m;
  }

  /// The filter for one photo: the collage-wide set, then the photo's own.
  /// Returns null when nothing changes the colours (skips the filter layer).
  static ColorFilter? filterFor(Adjustments global, Adjustments own) {
    if (global.isIdentity && own.isIdentity) return null;
    return ColorFilter.matrix(
        multiply(forAdjustments(own), forAdjustments(global)));
  }
}
