import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_photos.dart';

void main() {
  setUp(() => AppSettings.instance.resetForTest());

  group('ColorMatrix', () {
    test('identity adjustments need no filter', () {
      expect(ColorMatrix.filterFor(Adjustments(), Adjustments()), isNull);
      expect(ColorMatrix.forAdjustments(Adjustments()), ColorMatrix.identity);
    });

    test('multiplying by identity changes nothing', () {
      final m = ColorMatrix.saturation(0.4);
      expect(ColorMatrix.multiply(ColorMatrix.identity, m), m);
      expect(ColorMatrix.multiply(m, ColorMatrix.identity), m);
    });

    test('full desaturation gives identical R, G and B rows', () {
      final m = ColorMatrix.saturation(-1);
      expect(m.sublist(0, 5), m.sublist(5, 10));
      expect(m.sublist(5, 10), m.sublist(10, 15));
    });

    test('hue rotation of 0 and 360 degrees is identity', () {
      for (final deg in [0.0, 360.0]) {
        final m = ColorMatrix.hue(deg);
        for (var i = 0; i < 20; i++) {
          expect(m[i], closeTo(ColorMatrix.identity[i], 1e-9), reason: '$i');
        }
      }
    });

    test('a photo adjustment stacks on top of the collage one', () {
      final global = Adjustments(brightness: 0.5);
      final own = Adjustments(tone: ToneFilter.mono);
      expect(ColorMatrix.filterFor(global, own), isNotNull);
      expect(ColorMatrix.filterFor(global, Adjustments()), isNotNull);
    });
  });

  group('layouts', () {
    test('every preset has as many slots as its photo count', () {
      for (final p in layoutPresets) {
        expect(p.build().slotCount, p.count, reason: p.id);
      }
    });

    test('there are presets for 1 to 4 photos, default first', () {
      for (var n = 1; n <= 4; n++) {
        expect(presetsFor(n), isNotEmpty, reason: '$n');
      }
      expect(presetsFor(4).first.id, '4-grid');
    });

    test('build returns a fresh tree each time', () {
      final preset = presetsFor(2).first;
      final a = preset.build() as SplitNode;
      a.ratio = 0.8;
      expect((preset.build() as SplitNode).ratio, 0.5);
    });
  });

  group('dates', () {
    test('stamp format is dd.mm.yy', () {
      expect(formatStampDate(DateTime(2024, 5, 1)), '01.05.24');
      expect(formatStampDate(DateTime(1999, 12, 31)), '31.12.99');
    });

    test('parses EXIF dates', () {
      expect(PhotoLoader.parseExifDate('2023:07:04 18:22:01'),
          DateTime(2023, 7, 4));
      expect(PhotoLoader.parseExifDate('0000:00:00 00:00:00'), isNull);
      expect(PhotoLoader.parseExifDate(null), isNull);
    });

    test('parses camera file names', () {
      expect(PhotoLoader.parseFileNameDate('IMG_20240501_123456.jpg'),
          DateTime(2024, 5, 1));
      expect(PhotoLoader.parseFileNameDate('PXL_20251231_235959123.jpg'),
          DateTime(2025, 12, 31));
      expect(PhotoLoader.parseFileNameDate('Screenshot 2022-03-09 at 10.jpg'),
          DateTime(2022, 3, 9));
      expect(PhotoLoader.parseFileNameDate('holiday.jpg'), isNull);
    });
  });

  group('CollageController', () {
    test('adding photos picks the default layout for the count', () {
      final c = CollageController();
      c.addPhotos(samplePhotos(3));
      expect(c.photos.length, 3);
      expect(c.preset.count, 3);
      expect(c.layout.slotCount, 3);
      expect(c.selected, 0);
    });

    test('never holds more than 4 photos', () {
      final c = CollageController();
      c.addPhotos(samplePhotos(3));
      final dropped = c.addPhotos(samplePhotos(3));
      expect(dropped, 2);
      expect(c.photos.length, 4);
      expect(c.canAddMore, isFalse);
    });

    test('removing a photo re-lays out and keeps selection valid', () {
      final c = CollageController()..addPhotos(samplePhotos(2));
      c.select(1);
      c.removePhoto(1);
      expect(c.photos.length, 1);
      expect(c.preset.count, 1);
      expect(c.selected, 0);
      c.removePhoto(0);
      expect(c.isEmpty, isTrue);
      expect(c.selected, isNull);
    });

    test('swapping follows the selection', () {
      final c = CollageController()..addPhotos(samplePhotos(2));
      final first = c.photos[0];
      c.select(0);
      c.swapPhotos(0, 1);
      expect(c.photos[1], same(first));
      expect(c.selected, 1);
    });

    test('rotating swaps the oriented size and resets the crop', () {
      final c = CollageController()..addPhotos(samplePhotos(1));
      final p = c.photos.first..zoom = 3;
      expect(p.orientedSize, const Size(300, 200));
      c.rotate(p);
      expect(p.quarterTurns, 1);
      expect(p.orientedSize, const Size(200, 300));
      expect(p.zoom, 1);
      c.rotate(p, clockwise: false);
      expect(p.quarterTurns, 0);
    });

    test('color scope edits all photos or just the selected one', () {
      final c = CollageController()..addPhotos(samplePhotos(2));
      expect(c.editedAdjustments, same(c.globalAdjustments));
      c.select(1);
      c.colorScope = ColorScope.selected;
      expect(c.editedAdjustments, same(c.photos[1].adjustments));
    });

    test('date stamp placement can be copied to every photo', () {
      final c = CollageController()..addPhotos(samplePhotos(3));
      c.photos[0].stamp
        ..x = 0.1
        ..y = 0.2
        ..size = 0.09;
      c.applyStampToAll(c.photos[0]);
      for (final p in c.photos) {
        expect([p.stamp.x, p.stamp.y, p.stamp.size], [0.1, 0.2, 0.09]);
      }
      // Copies, not shared objects.
      c.photos[1].stamp.x = 0.5;
      expect(c.photos[2].stamp.x, 0.1);
    });

    test('new collages follow the date-stamp setting', () {
      AppSettings.instance.dateStampByDefault = true;
      final c = CollageController()..addPhotos(samplePhotos(1));
      expect(c.showDates, isTrue);
    });
  });

  test('saved file name is timestamped', () {
    expect(CollageSaver.fileName(DateTime(2026, 10, 6, 9, 5, 3)),
        'BestCollage_20261006_090503.png');
  });
}
