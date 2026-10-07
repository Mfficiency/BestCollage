import 'package:best_collage/best_collage.dart';
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

  Future<CollageController> pumpPage(WidgetTester tester,
      {int photos = 0}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = CollageController();
    if (photos > 0) c.addPhotos(samplePhotos(photos));
    await tester.pumpWidget(MaterialApp(
      home: CollagePage(
        controller: c,
        picker: (max) async => samplePhotos(max),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('empty state picks photos and shows the editor', (tester) async {
    final c = await pumpPage(tester);
    expect(find.text('Make a collage'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Choose photos'));
    await tester.pumpAndSettle();

    expect(c.photos.length, 4);
    expect(find.byType(PhotoCell), findsNWidgets(4));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Layout'), findsWidgets);
  });

  testWidgets('dragging a divider resizes the photos', (tester) async {
    final c = await pumpPage(tester, photos: 2);
    final split = c.layout as SplitNode;
    expect(split.ratio, 0.5);

    final handle = find.byKey(const Key('divider-handle'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(split.ratio, greaterThan(0.6));
  });

  testWidgets('picking another layout and shape', (tester) async {
    final c = await pumpPage(tester, photos: 2);
    await tester.tap(find.byTooltip('Stacked'));
    await tester.pumpAndSettle();
    expect(c.preset.id, '2-stack');
    expect((c.layout as SplitNode).axis, Axis.vertical);

    await tester.tap(find.widgetWithText(ChoiceChip, '4:5'));
    await tester.pumpAndSettle();
    expect(c.shape.label, '4:5');
  });

  testWidgets('photo tool rotates and zooms the selected photo',
      (tester) async {
    final c = await pumpPage(tester, photos: 2);
    await tester.tap(find.byType(PhotoCell).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(c.selected, 1);

    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Rotate right'));
    await tester.pumpAndSettle();
    expect(c.photos[1].quarterTurns, 1);

    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(c.photos[1].zoom, greaterThan(1));

    await tester.tap(find.text('Reset crop'));
    await tester.pumpAndSettle();
    expect(c.photos[1].zoom, 1);
  });

  testWidgets('color tool edits all photos or only the selected one',
      (tester) async {
    final c = await pumpPage(tester, photos: 2);
    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
        find.text('B&W'), find.byType(ListView), const Offset(-100, 0));
    await tester.ensureVisible(find.text('B&W'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B&W'));
    await tester.pumpAndSettle();
    expect(c.globalAdjustments.tone, ToneFilter.mono);
    expect(find.byType(ColorFiltered), findsWidgets);

    await tester.ensureVisible(find.text('Photo 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo 1'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
        find.text('Sepia'), find.byType(ListView), const Offset(-100, 0));
    await tester.ensureVisible(find.text('Sepia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();
    expect(c.photos[0].adjustments.tone, ToneFilter.sepia);
    expect(c.photos[1].adjustments.tone, ToneFilter.original);
    expect(c.globalAdjustments.tone, ToneFilter.mono);
  });

  testWidgets('date tool shows dd.mm.yy stamps', (tester) async {
    final c = await pumpPage(tester, photos: 2);
    expect(find.text('01.05.24'), findsNothing);

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show date taken'));
    await tester.pumpAndSettle();
    expect(c.showDates, isTrue);
    expect(find.text('01.05.24'), findsWidgets);
    expect(find.text('24.12.23'), findsOneWidget);

    // Hide it on the selected photo only.
    await tester.tap(find.widgetWithText(SwitchListTile, '01.05.24'));
    await tester.pumpAndSettle();
    expect(c.photos[0].showDate, isFalse);
    expect(find.byKey(const Key('date-stamp-0')), findsNothing);
    expect(find.byKey(const Key('date-stamp-1')), findsOneWidget);
  });

  testWidgets('dragging a date stamp moves it', (tester) async {
    final c = await pumpPage(tester, photos: 1);
    c.showDates = true;
    c.changed();
    await tester.pumpAndSettle();
    final before = c.photos[0].stamp.x;
    await tester.drag(
        find.byKey(const Key('date-stamp-0')), const Offset(-120, -60));
    await tester.pumpAndSettle();
    expect(c.photos[0].stamp.x, lessThan(before));
  });

  testWidgets('drawer lists the technical pages and opens them',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.textContaining('BestCollage v0.1.0+1'), findsOneWidget);
    for (final label in const [
      'Settings',
      'About',
      'Changelog',
      'App Logs',
      'Startup Times',
      'Test Results',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });
}
