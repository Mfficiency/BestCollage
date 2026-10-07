import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('1.0.0', '1');
  });
  tearDown(AppVersion.resetForTest);

  testWidgets('renders section chips and settings controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    // Section chips.
    for (final title in const ['Appearance', 'Collage', 'Updates', 'Data']) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    // A few representative controls from the first (visible) section.
    expect(find.text('Minimalist mode'), findsOneWidget);
    expect(find.text('24-hour time'), findsOneWidget);
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

    expect(AppSettings.instance.minimalist, isFalse);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Minimalist mode'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.minimalist, isTrue);
  });

  testWidgets('selecting the dark theme segment updates settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
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
}
