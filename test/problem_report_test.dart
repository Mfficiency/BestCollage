import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Report a problem to Claude": a double tap on the version in the drawer
/// opens the report sheet; Settings › Debugging holds the token and explains it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('1.0.0', '1');
    AppUpdates.resetForTest();
  });
  tearDown(() {
    AppUpdates.resetForTest();
    AppVersion.resetForTest();
  });

  testWidgets('double tap on the version in the drawer opens the report',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
    ));
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffold.openDrawer();
    await tester.pumpAndSettle();

    final version = find.byKey(const Key('problemReport.trigger'));
    expect(version, findsOneWidget);
    await tester.tap(version);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(version);
    await tester.pumpAndSettle();

    expect(find.text('Report a problem to Claude'), findsOneWidget);
    expect(find.text('Send to Claude'), findsOneWidget);
    expect(find.text("Include the app's logs"), findsOneWidget);
  });

  testWidgets('settings row explains the problem-report token',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    final expand = find.byTooltip('Expand Debugging');
    await tester.ensureVisible(expand);
    await tester.pumpAndSettle();
    await tester.tap(expand);
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('problemReport.settings'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: tile, matching: find.text('GitHub token')),
        findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('No token')),
        findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The package's one token dialog: the field first, show and copy,
    // Close always there; the steps folded under "How to get a token".
    expect(find.byType(GithubTokenDialog), findsOneWidget);
    expect(find.byKey(const Key('githubToken.show')), findsOneWidget);
    expect(find.byKey(const Key('githubToken.copy')), findsOneWidget);
    expect(find.byKey(const Key('githubToken.close')), findsOneWidget);
    expect(find.text('Create a token on GitHub'), findsNothing);
    await tester.tap(find.byKey(const Key('githubToken.howTo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Issues: "Read and write"'), findsWidgets);
    expect(find.text('Create a token on GitHub'), findsOneWidget);
  });

  test('the problem-report token lives in secure storage, not prefs',
      () async {
    final tokens = MemoryUpdateTokenStore();
    final u = AppUpdates.create(tokens: tokens);
    await u.problemReport.setToken(' github_pat_x ');
    expect(tokens.values[AppUpdates.problemReportTokenKey], 'github_pat_x');
    expect(await u.problemReport.token(), 'github_pat_x');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    await u.problemReport.setToken('');
    expect(tokens.values, isEmpty);
    expect(u.problemReport.config.githubRepo, 'Mfficiency/BestCollage');
    u.controller.dispose();
  });

  test('the report logs carry the App Logs, newest last', () async {
    LogService.clear();
    LogService.add('test', 'first');
    LogService.add('test', 'second');
    final logs = await AppUpdates.collectLogs();
    expect(logs, contains('== App Logs'));
    expect(logs.indexOf('first'), lessThan(logs.indexOf('second')));
    LogService.clear();
  });
}
