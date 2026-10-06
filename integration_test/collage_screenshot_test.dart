import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/collage/test_photos.dart';

/// Real-font screenshots of the collage editor, one per tool:
///
///   flutter test integration_test/collage_screenshot_test.dart -d windows
///
/// → build/e2e_screenshots_device/*.png
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('collage editor screenshots', (tester) async {
    AppSettings.instance.resetForTest();
    final key = GlobalKey();
    final folder = Directory('build/e2e_screenshots_device')
      ..createSync(recursive: true);

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${folder.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List(), flush: true);
        image.dispose();
      });
    }

    final c = CollageController()..addPhotos(samplePhotos(3));
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: Center(
        child: SizedBox(
          width: 390,
          height: 844,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(AppSettings.instance),
            home: CollagePage(controller: c),
          ),
        ),
      ),
    ));
    await capture('layout');

    await tester.tap(find.text('Photo'));
    await capture('photo');

    await tester.tap(find.text('Color'));
    await capture('color');

    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show date taken'));
    await capture('date');
  });
}
