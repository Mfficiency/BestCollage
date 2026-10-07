import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_photos.dart';

/// Sample photos with fake paths, so a saved state can be "reloaded".
List<PhotoItem> pathPhotos([int count = 4]) => [
      for (final (i, p) in samplePhotos(count).indexed)
        PhotoItem(
          path: 'mem://$i',
          image: p.image,
          pixelSize: p.pixelSize,
          takenAt: p.takenAt,
          dateSource: p.dateSource,
        ),
    ];

/// Reloads `mem://i` paths as fresh sample photos (like opening the files).
List<PhotoItem?> reload(Map<String, dynamic> state, {Set<int> gone = const {}}) {
  final fresh = samplePhotos();
  return [
    for (final path in CollageController.photoPaths(state))
      if (int.tryParse(path.replaceFirst('mem://', '')) case final i?)
        gone.contains(i)
            ? null
            : PhotoItem(
                path: path,
                image: fresh[i].image,
                pixelSize: fresh[i].pixelSize,
                dateSource: DateSource.unknown,
              )
      else
        null,
  ];
}

/// An edited 3-photo collage with every kind of setting changed.
CollageController editedCollage() {
  final c = CollageController()..addPhotos(pathPhotos(3));
  c.usePreset(layoutPresets.firstWhere((p) => p.id == '3-top'));
  final root = c.layout as SplitNode;
  root.ratio = 0.72;
  (root.second as SplitNode).ratio = 0.3;
  c
    ..shape = CanvasShape.all.firstWhere((s) => s.label == '9:16')
    ..border = 14
    ..cornerRadius = 9
    ..borderColor = borderColors[2]
    ..showDates = true
    ..dateColor = dateStampColors[3]
    ..colorScope = ColorScope.selected
    ..selected = 2
    ..historyId = 'abc';
  c.globalAdjustments
    ..tone = ToneFilter.vintage
    ..saturation = -0.4;
  final p = c.photos[1];
  p
    ..quarterTurns = 3
    ..flipped = true
    ..zoom = 2.5
    ..alignX = -0.6
    ..alignY = 0.8
    ..showDate = false
    ..takenAt = DateTime(2020, 2, 29)
    ..dateSource = DateSource.manual
    ..stamp = DateStampPlacement(x: 0.1, y: 0.2, size: 0.08);
  p.adjustments
    ..tone = ToneFilter.mono
    ..hue = 45
    ..brightness = 0.25
    ..warmth = -0.5;
  return c;
}

void main() {
  setUp(AppSettings.instance.resetForTest);

  group('collage state', () {
    test('survives a JSON round trip with every setting', () {
      final saved = jsonDecode(jsonEncode(editedCollage().toJson()))
          as Map<String, dynamic>;
      final c = CollageController();
      expect(c.restore(saved, reload(saved)), 0);

      expect(c.photos.map((p) => p.path), ['mem://0', 'mem://1', 'mem://2']);
      expect(c.preset.id, '3-top');
      final root = c.layout as SplitNode;
      expect(root.axis, Axis.vertical);
      expect(root.ratio, 0.72);
      expect((root.second as SplitNode).ratio, 0.3);
      expect(c.shape.label, '9:16');
      expect(identical(c.shape, CanvasShape.all[3]), isTrue);
      expect(c.border, 14);
      expect(c.cornerRadius, 9);
      expect(c.borderColor, borderColors[2]);
      expect(c.showDates, isTrue);
      expect(c.dateColor, dateStampColors[3]);
      expect(c.colorScope, ColorScope.selected);
      expect(c.selected, 2);
      expect(c.historyId, 'abc');
      expect(c.globalAdjustments.tone, ToneFilter.vintage);
      expect(c.globalAdjustments.saturation, -0.4);

      final p = c.photos[1];
      expect(p.quarterTurns, 3);
      expect(p.flipped, isTrue);
      expect(p.zoom, 2.5);
      expect(p.alignX, -0.6);
      expect(p.alignY, 0.8);
      expect(p.showDate, isFalse);
      expect(p.takenAt, DateTime(2020, 2, 29));
      expect(p.dateSource, DateSource.manual);
      expect(p.stamp.x, 0.1);
      expect(p.stamp.y, 0.2);
      expect(p.stamp.size, 0.08);
      expect(p.adjustments.tone, ToneFilter.mono);
      expect(p.adjustments.hue, 45);
      expect(p.adjustments.brightness, 0.25);
      expect(p.adjustments.warmth, -0.5);
      // Untouched photos keep their EXIF date.
      expect(c.photos[0].takenAt, DateTime(2024, 5, 1));
      expect(c.photos[0].dateSource, DateSource.exif);
    });

    test('a missing photo drops out and the layout fits the rest', () {
      final saved = editedCollage().toJson();
      final c = CollageController();
      expect(c.restore(saved, reload(saved, gone: {1})), 1);
      expect(c.photos.map((p) => p.path), ['mem://0', 'mem://2']);
      expect(c.preset.count, 2);
      expect(c.layout.slotCount, 2);
      // Style still comes back.
      expect(c.shape.label, '9:16');
      expect(c.border, 14);
    });

    test('a broken layout falls back to the preset', () {
      final saved = editedCollage().toJson()
        ..['layout'] = {'axis': 'diagonal'}
        ..['border'] = 500
        ..['borderColor'] = 0x12345678;
      final c = CollageController();
      c.restore(saved, reload(saved));
      expect(c.preset.id, '3-top');
      expect((c.layout as SplitNode).ratio, 0.6);
      expect(c.border, 24);
      expect(c.borderColor, borderColors.first);
    });

    test('style settings come back even without photos', () {
      final c = editedCollage()..clear();
      final saved = c.toJson();
      final r = CollageController()..restore(saved, const []);
      expect(r.isEmpty, isTrue);
      expect(r.shape.label, '9:16');
      expect(r.border, 14);
      expect(r.historyId, isNull);
    });
  });

  group('FileCollageStore', () {
    late Directory dir;
    late FileCollageStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('collage_store');
      store = FileCollageStore(baseDir: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps the draft across restarts', () async {
      expect(await store.loadDraft(), isNull);
      final state = editedCollage().toJson();
      await store.saveDraft(state);
      final again = FileCollageStore(baseDir: () async => dir);
      expect(jsonEncode(await again.loadDraft()), jsonEncode(state));
    });

    test('history: add, update, delete — newest first', () async {
      final a = await store.saveToHistory({'shape': '4:5', 'photos': []},
          thumbnail: Uint8List.fromList([1, 2, 3]));
      final b = await store.saveToHistory({'shape': '1:1', 'photos': []});
      expect(a.state['historyId'], a.id);
      expect(a.aspectRatio, 0.8);
      expect(a.thumbnail, isA<FileImage>());
      expect(b.thumbnail, isNull);

      final again = FileCollageStore(baseDir: () async => dir);
      expect((await again.loadHistory()).map((e) => e.id), [b.id, a.id]);

      // Saving again under the same id updates it and moves it to the top.
      final a2 = await again.saveToHistory({'shape': '16:9', 'photos': []},
          id: a.id, thumbnail: Uint8List.fromList([4, 5]));
      expect(a2.id, a.id);
      expect(a2.createdAt, a.createdAt);
      final list = await again.loadHistory();
      expect(list.map((e) => e.id), [a.id, b.id]);
      expect(list.first.state['shape'], '16:9');
      final thumbs = Directory('${dir.path}/thumbs').listSync();
      expect(thumbs, hasLength(1), reason: 'old preview replaced');

      await again.deleteFromHistory(a.id);
      expect((await again.loadHistory()).map((e) => e.id), [b.id]);
      expect(Directory('${dir.path}/thumbs').listSync(), isEmpty);
    });

    test('photos are copied in and pruned when nothing uses them', () async {
      final src = File('${dir.path}/IMG_20240501_120000.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final kept1 = await store.keepPhoto(src.path);
      final kept2 = await store.keepPhoto(src.path);
      final kept3 = await store.keepPhoto(src.path);
      expect(kept1, isNot(src.path));
      expect(kept1, contains('/photos/'));
      expect(kept1, endsWith('_IMG_20240501_120000.jpg'));
      expect(File(kept1).readAsBytesSync(), [1, 2, 3]);
      expect(await store.keepPhoto(kept1), kept1, reason: 'already kept');

      await store.saveDraft({
        'photos': [
          {'path': kept1}
        ]
      });
      await store.saveToHistory({
        'photos': [
          {'path': kept2}
        ]
      });
      await store.prune(inUse: [kept3]);
      expect(File(kept1).existsSync(), isTrue);
      expect(File(kept2).existsSync(), isTrue);
      expect(File(kept3).existsSync(), isTrue);

      await store.prune();
      expect(File(kept3).existsSync(), isFalse);
      expect(src.existsSync(), isTrue, reason: 'originals are never touched');
    });

    test('a corrupt file reads as empty instead of crashing', () async {
      File('${dir.path}/draft.json').writeAsStringSync('{not json');
      File('${dir.path}/history.json').writeAsStringSync('[{"id": 3}]');
      expect(await store.loadDraft(), isNull);
      expect(await store.loadHistory(), isEmpty);
    });
  });

  group('page', () {
    late MemoryCollageStore store;

    setUp(() {
      store = MemoryCollageStore();
      CollageStore.instance = store;
      AppVersion.setForTest('0.1.0', '1');
    });
    tearDown(AppVersion.resetForTest);

    Future<CollageController> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = CollageController();
      await tester.pumpWidget(MaterialApp(
        home: CollagePage(
          controller: c,
          store: store,
          picker: (max) async => pathPhotos(max),
          resolver: (path) async => reload({
            'photos': [
              {'path': path}
            ]
          }).first,
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('reopens the last collage exactly as it was', (tester) async {
      store.draft = editedCollage().toJson();
      final c = await pumpPage(tester);
      expect(c.photos, hasLength(3));
      expect(find.byType(PhotoCell), findsNWidgets(3));
      expect((c.layout as SplitNode).ratio, 0.72);
      expect(c.shape.label, '9:16');
      expect(c.photos[1].zoom, 2.5);
    });

    testWidgets('edits are saved as you go', (tester) async {
      final c = await pumpPage(tester);
      await tester.tap(find.text('Choose photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '4:5'));
      await tester.pump(const Duration(seconds: 1));
      expect(store.draft?['shape'], '4:5');
      expect(CollageController.photoPaths(store.draft!), hasLength(4));

      (c.layout as SplitNode).ratio = 0.33;
      c.changed();
      await tester.pump(const Duration(seconds: 1));
      expect(store.draft?['layout']['ratio'], 0.33);
    });

    testWidgets('previous collages: listed, opened and deleted',
        (tester) async {
      final first = await store.saveToHistory(editedCollage().toJson());
      final second = await store.saveToHistory(
          (CollageController()..addPhotos(pathPhotos(2))).toJson());
      final c = await pumpPage(tester);

      // The empty screen offers the recent ones.
      expect(find.text('Previous collages'), findsOneWidget);
      expect(find.text('See all (2)'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous collages'));
      await tester.pumpAndSettle();
      expect(find.byType(CollageHistoryTile), findsNWidgets(2));
      expect(find.text('3 photos'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete collage').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.history.map((e) => e.id), [first.id]);
      expect(second.id, isNot(first.id));
      expect(find.byType(CollageHistoryTile), findsOneWidget);

      await tester.tap(find.byType(CollageHistoryTile));
      await tester.pumpAndSettle();
      expect(c.photos, hasLength(3));
      expect(c.historyId, first.id);
      expect(c.shape.label, '9:16');
      expect(find.byType(PhotoCell), findsNWidgets(3));
    });

    testWidgets('opening a saved collage asks before replacing the current one',
        (tester) async {
      await store.saveToHistory(editedCollage().toJson());
      final c = await pumpPage(tester);
      await tester.tap(find.text('Choose photos'));
      await tester.pumpAndSettle();
      expect(c.photos, hasLength(4));

      await tester.tap(find.byTooltip('Previous collages'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CollageHistoryTile));
      await tester.pumpAndSettle();
      expect(find.text('Open this collage?'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(c.photos, hasLength(3));
    });

    testWidgets('saving adds the collage to previous collages, once',
        (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppSettings.instance.exportLongEdge = 1080;
      final c = CollageController()..addPhotos(pathPhotos(2));
      var saved = 0;
      await tester.pumpWidget(MaterialApp(
        home: CollagePage(
          controller: c,
          store: store,
          // Real rendering is engine work that never finishes in the
          // fake-async zone; the canvas itself is covered elsewhere.
          renderer: (boundary, edge) async => Uint8List.fromList([edge % 256]),
          saver: (png) async {
            expect(png, [1080 % 256]);
            saved++;
            return 'Gallery';
          },
        ),
      ));
      await tester.pumpAndSettle();

      Future<void> save() async {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }

      await save();
      expect(saved, 1);
      expect(store.history, hasLength(1));
      expect(c.historyId, store.history.first.id);
      expect(store.history.first.thumbnail, isA<MemoryImage>());
      expect((store.history.first.thumbnail as MemoryImage).bytes, [480 % 256]);
      expect(find.text('Saved to Gallery'), findsOneWidget);

      // Saving the same collage again updates its entry.
      c.border = 20;
      c.changed();
      await save();
      expect(saved, 2);
      expect(store.history, hasLength(1));
      expect(store.history.first.state['border'], 20);
    });

    testWidgets('the drawer opens previous collages', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous collages'));
      await tester.pumpAndSettle();
      expect(find.text('No collages yet'), findsOneWidget);
    });
  });
}
