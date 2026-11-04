import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppVersion.setForTest('2.1.0', '9'));
  tearDown(() {
    AppVersion.resetForTest();
    AppUpdates.resetForTest();
  });

  testWidgets('shows app name, version and action buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text(AppConfig.appName), findsOneWidget);
    expect(find.textContaining('v2.1.0+9'), findsOneWidget);
    expect(find.text('Replay Introduction'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('ends with Other apps, which lists the other apps',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    final link = find.byKey(const Key('otherApps.link'));
    await tester.scrollUntilVisible(link, 300);
    // The last tile on the page.
    expect(tester.widget(find.byType(ListTile).last).key,
        const Key('otherApps.link'));

    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Other apps'), findsOneWidget);
    expect(find.text('BestToDo'), findsOneWidget);
    expect(find.text('BestCollage'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Hally Remote'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Hally Remote'), findsOneWidget);
  });
}
