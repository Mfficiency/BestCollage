import 'package:best_collage/best_collage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_photos.dart';

void main() {
  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('0.1.0', '1');
    CollageStore.instance = MemoryCollageStore();
  });
  tearDown(AppVersion.resetForTest);

  group('undo / redo', () {
    CollageController withPhotos([int n = 2]) {
      final c = CollageController()..addPhotos(samplePhotos(n));
      c.checkpoint();
      return c;
    }

    test('an empty collage is never an undo step', () {
      final c = withPhotos();
      expect(c.canUndo, isFalse);
      c.undo();
      expect(c.photos.length, 2);
    });

    test('undo and redo step through the checkpoints', () {
      final c = withPhotos();
      c.border = 12;
      c.checkpoint();
      c.sideBorder = 30;
      c.checkpoint();
      expect(c.canUndo, isTrue);
      expect(c.canRedo, isFalse);

      c.undo();
      expect(c.sideBorder, 6);
      expect(c.border, 12);
      c.undo();
      expect(c.border, 6);
      expect(c.canUndo, isFalse);

      c.redo();
      c.redo();
      expect(c.border, 12);
      expect(c.sideBorder, 30);
      expect(c.canRedo, isFalse);
    });

    test('undo keeps an edit not yet checkpointed', () {
      final c = withPhotos();
      c.cornerRadius = 10;
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.cornerRadius, 0);
      c.redo();
      expect(c.cornerRadius, 10);
    });

    test('a new edit after undo drops the redo steps', () {
      final c = withPhotos();
      c.border = 12;
      c.checkpoint();
      c.undo();
      c.border = 3;
      expect(c.canRedo, isFalse);
      c.checkpoint();
      c.redo();
      expect(c.border, 3);
    });

    test('photo edits, removals and layout come back', () {
      final c = withPhotos(3);
      final second = c.photos[1];
      (c.layout as SplitNode).ratio = 0.7;
      c.rotate(c.photos[0]);
      c.photos[0].adjustments.hue = 40;
      c.checkpoint();
      c.removePhoto(1);
      c.checkpoint();
      expect(c.photos.length, 2);

      c.undo();
      expect(c.photos.length, 3);
      expect(identical(c.photos[1], second), isTrue);
      expect((c.layout as SplitNode).ratio, 0.7);
      expect(c.photos[0].quarterTurns, 1);
      expect(c.photos[0].adjustments.hue, 40);

      c.undo();
      expect(c.photos[0].quarterTurns, 0);
      expect(c.photos[0].adjustments.hue, 0);
    });

    test('selecting a photo is not an undo step', () {
      final c = withPhotos();
      c.select(1);
      expect(c.canUndo, isFalse);
    });

    test('opening a collage or starting a new one forgets the steps', () {
      final c = withPhotos();
      c.border = 12;
      c.checkpoint();
      c.restore(c.toJson(), List.of(c.photos));
      expect(c.canUndo, isFalse);
      c.clear();
      expect(c.canUndo, isFalse);
    });
  });

  group('borders', () {
    test('sides and top & bottom are saved and restored', () {
      final c = CollageController()
        ..addPhotos(samplePhotos(1))
        ..border = 4
        ..sideBorder = 20
        ..topBottomBorder = 40;
      final r = CollageController()..restore(c.toJson(), samplePhotos(1));
      expect(r.border, 4);
      expect(r.sideBorder, 20);
      expect(r.topBottomBorder, 40);
    });

    test('a collage from before uses its one width everywhere', () {
      final c = CollageController()..addPhotos(samplePhotos(1));
      final old = c.toJson()
        ..['border'] = 9
        ..remove('sideBorder')
        ..remove('topBottomBorder');
      final r = CollageController()..restore(old, samplePhotos(1));
      expect(r.sideBorder, 9);
      expect(r.topBottomBorder, 9);
    });
  });

  group('page', () {
    Future<CollageController> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = CollageController()..addPhotos(samplePhotos(2));
      await tester.pumpWidget(MaterialApp(
        home: CollagePage(
          controller: c,
          picker: (max) async => samplePhotos(max),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('Undo and Redo buttons', (tester) async {
      final c = await pumpPage(tester);
      final split = c.layout as SplitNode;
      await tester.drag(
          find.byKey(const Key('divider-handle')), const Offset(80, 0));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(split.ratio, greaterThan(0.6));

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect((c.layout as SplitNode).ratio, 0.5);

      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect((c.layout as SplitNode).ratio, greaterThan(0.6));
    });

    testWidgets('zooming the view leaves the collage alone', (tester) async {
      final c = await pumpPage(tester);
      await tester.tap(find.byTooltip('Zoom the view'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zoom-view')), findsOneWidget);

      // A drag over the divider pans the view, it doesn't move the divider.
      await tester.drag(
          find.byKey(const Key('divider-handle')), const Offset(80, 0),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect((c.layout as SplitNode).ratio, 0.5);

      // Zoom in with the mouse wheel.
      final center = tester.getCenter(find.byType(CollageCanvas));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to editing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zoom-view')), findsNothing);
      // Still zoomed: the collage is drawn bigger than before.
      expect(find.byTooltip('Fit to screen'), findsOneWidget);
      await tester.tap(find.byTooltip('Fit to screen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fit to screen'), findsNothing);
      expect(c.photos.length, 2);
    });

    testWidgets('border sliders say and show which border they change',
        (tester) async {
      final c = await pumpPage(tester);
      expect(find.text('Between photos'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Top & bottom'), 50,
          scrollable: find.byType(Scrollable).last);
      expect(find.byType(BorderDiagram), findsNWidgets(3));

      final slider = find.ancestor(
          of: find.text('Left & right'), matching: find.byType(Row)).first;
      final gesture = await tester.startGesture(
          tester.getCenter(find.descendant(
              of: slider, matching: find.byType(Slider))));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(c.highlightedBorder, BorderPart.sides);
      expect(find.byKey(const Key('border-highlight')), findsNWidgets(2));
      await gesture.up();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(c.highlightedBorder, isNull);
      expect(find.byKey(const Key('border-highlight')), findsNothing);
      expect(c.sideBorder, greaterThan(6));
      expect(c.border, 6);
      expect(c.topBottomBorder, 6);
    });
  });
}
