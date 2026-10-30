import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart' show UpdatePlatform;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('1.0.0', '1');
  });
  tearDown(() {
    AppVersion.resetForTest();
    AppUpdates.resetForTest();
  });

  /// The titles of every row, top to bottom, under each section header.
  Map<String, List<String>> rowsBySection(WidgetTester tester) {
    final out = <String, List<String>>{};
    for (final section in tester.widgetList<SettingsSection>(
        find.byType(SettingsSection))) {
      final tiles = find.descendant(
        of: find.byWidget(section),
        // A SwitchListTile draws a ListTile too.
        matching: find.byType(ListTile),
      );
      out[section.title] = [
        for (final e in tiles.evaluate())
          switch (e.widget) {
            ListTile(:final Text title) => title.data ?? '',
            _ => '',
          },
      ]..removeWhere((t) => t.isEmpty);
    }
    return out;
  }

  testWidgets('renders section chips and settings controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();

    // Section chips.
    for (final title in const [
      'Appearance',
      'Collage',
      'Debugging',
      'Updates',
      'Backup & data'
    ]) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    // A few representative controls from the first section.
    expect(find.text('Minimalist mode'), findsOneWidget);
    expect(find.text('Time format'), findsOneWidget);
    expect(find.text('Compact mode'), findsOneWidget);
    expect(find.text('Date format'), findsOneWidget);

    // Jump to the Collage section via its chip and confirm its controls.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Collage'));
    await tester.pumpAndSettle();
    expect(find.text('Export size'), findsOneWidget);
    expect(find.text('Date stamp on new collages'), findsOneWidget);
  });

  testWidgets('toggling minimalist updates settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.minimalist, isFalse);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Minimalist mode'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.minimalist, isTrue);
  });

  testWidgets('selecting the dark theme segment updates settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dark'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, AppThemeMode.dark);
  });

  testWidgets('search filters settings and lists a match', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'resolution');
    await tester.pumpAndSettle();

    // The result tile for "Export size" appears (under its section subtitle).
    expect(find.text('Export size'), findsOneWidget);
    expect(find.text('Collage'), findsWidgets);
  });

  testWidgets(
      'sections: Appearance first; Debugging, Updates, Backup & data last',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips,
        ['Appearance', 'Collage', 'Debugging', 'Updates', 'Backup & data']);

    // The cards are in the same order as the chips.
    final cardTops = [
      for (final t in chips) tester.getTopLeft(find.byTooltip('Expand $t')).dy,
    ];
    expect(cardTops, orderedEquals([...cardTops]..sort()));
  });

  testWidgets('sections start collapsed and open one by one or all at once',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Minimalist mode'), findsNothing);
    expect(find.text('Export size'), findsNothing);
    expect(find.text('Expand all'), findsOneWidget);

    // Opening Appearance shows its rows, the others stay collapsed.
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Minimalist mode'), findsOneWidget);
    expect(find.text('Export size'), findsNothing);
    await tester.tap(find.byTooltip('Collapse Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Minimalist mode'), findsNothing);

    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('Minimalist mode'), findsOneWidget);
    expect(find.text('Export size'), findsOneWidget);
    expect(find.text('Collapse all'), findsOneWidget);

    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('Minimalist mode'), findsNothing);

    // Opening Settings again starts collapsed again.
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(
        home: SettingsPage(key: ValueKey('reopened'))));
    await tester.pumpAndSettle();
    expect(find.text('Minimalist mode'), findsNothing);
  });

  testWidgets('a search result opens its folded section', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'automatic');
    await tester.pumpAndSettle();
    expect(find.text('Automatically check for updates'), findsOneWidget);

    await tester.tap(find.text('Automatically check for updates'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(
        find.widgetWithText(SwitchListTile, 'Automatically check for updates'),
        findsOneWidget);
    // Only Updates opened.
    expect(find.text('Minimalist mode'), findsNothing);
  });

  testWidgets('no match says so', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No settings match your search'), findsOneWidget);
  });

  testWidgets('every section has the standard rows in the standard order',
      (tester) async {
    // Like a phone, so the full backup's rows show.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    AppUpdates.instance = AppUpdates.create(
      prefs: prefs,
      platform: UpdatePlatform(supported: true),
      backupRoots: () async => const {},
    );
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();

    expect(rowsBySection(tester), {
      'Appearance': [
        'Compact mode',
        'Time format',
        'Date format',
        'Minimalist mode',
      ],
      'Collage': ['Export size', 'Date stamp on new collages'],
      'Debugging': ['Send a report', 'GitHub token'],
      'Updates': [
        'Automatically check for updates',
        'Check for updates',
        'GitHub token',
      ],
      'Backup & data': [
        'Back up everything',
        'Restore from a backup',
        'Backup location',
        'Automatic backup',
        'Last backup',
        'Export everything',
        'Export settings',
        'Import',
      ],
    });
    // Theme (dark mode) is the first row of Appearance (a segmented row).
    final theme = tester.getTopLeft(find.text('Theme')).dy;
    expect(theme, lessThan(tester.getTopLeft(find.text('Compact mode')).dy));
  });

  testWidgets('compact mode and time format work app-wide', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Compact mode'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.compact, isTrue);
    expect(AppTheme.light(AppSettings.instance).visualDensity,
        VisualDensity.compact);
    expect(AppTheme.dark(AppSettings.instance).visualDensity,
        VisualDensity.compact);
    expect(AppSettings.instance.toMap()['compact'], isTrue);

    expect(find.text('14:30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.timeFormat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12-hour').last);
    await tester.pumpAndSettle();
    expect(AppSettings.instance.use24HourFormat, isFalse);
    expect(formatTime(DateTime(2026, 3, 9, 14, 30)), '2:30 PM');
  });
}
