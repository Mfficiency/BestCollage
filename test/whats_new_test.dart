import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What's new: after an update, once, the changelog entries since the
/// version the user had before; Settings › Releases turns it off.
void main() {
  const changelog = '''
# Changelog

## [1.2.0] - 2026-10-30
- Newest change

## [1.1.0] - 2026-10-20
- Middle change

## [1.0.0] - 2026-10-10
- Old change
''';

  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('1.2.0', '3');
  });
  tearDown(AppVersion.resetForTest);

  /// Runs [maybeShowWhatsNew] after the first frame, with [changelog] as
  /// the bundled CHANGELOG.md.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _ChangelogBundle(changelog),
      child: MaterialApp(
        home: Builder(builder: (context) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => maybeShowWhatsNew(context));
          return const Scaffold();
        }),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('releasesSince lists the versions after the previous one', () {
    final all = parseChangelog(changelog);
    expect(releasesSince(all, '1.0.0', '1.2.0').map((r) => r.title),
        ['1.2.0', '1.1.0']);
    expect(releasesSince(all, '1.2.0', '1.2.0'), isEmpty);
    expect(compareVersions('1.10.0', '1.9.2'), 1);
  });

  test('on by default', () {
    expect(AppSettings.instance.whatsNew, isTrue);
  });

  testWidgets('shown once after an update, with the entries since then',
      (tester) async {
    SharedPreferences.setMockInitialValues({whatsNewLastVersionKey: '1.0.0'});
    await launch(tester);

    expect(find.byType(WhatsNewSheet), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('Newest change'), findsOneWidget);
    expect(find.text('Middle change'), findsOneWidget);
    expect(find.text('Old change'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(whatsNewLastVersionKey), '1.2.0');

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewSheet), findsNothing);

    // The next start of the same version shows nothing.
    await tester.pumpWidget(const SizedBox());
    await launch(tester);
    expect(find.byType(WhatsNewSheet), findsNothing);
  });

  testWidgets('not shown when turned off in Settings', (tester) async {
    SharedPreferences.setMockInitialValues({whatsNewLastVersionKey: '1.0.0'});
    AppSettings.instance.whatsNew = false;
    await launch(tester);

    expect(find.byType(WhatsNewSheet), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(whatsNewLastVersionKey), '1.2.0');
  });

  testWidgets('not shown on a new install', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);

    expect(find.byType(WhatsNewSheet), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(whatsNewLastVersionKey), '1.2.0');
  });
}

class _ChangelogBundle extends CachingAssetBundle {
  _ChangelogBundle(this.changelog);
  final String changelog;

  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('not in this test bundle: $key');

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      key == 'CHANGELOG.md' ? changelog : throw FlutterError(key);
}
