import 'package:best_collage/best_collage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart' show RemainingTime;

void main() {
  late DateTime now;
  setUp(() => now = DateTime(2026, 10, 15, 12));

  Future<void> pump(WidgetTester tester, RemainingTime eta,
      {double? done, Duration? typical}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RemainingTimeText(
            eta: eta, done: done, typical: typical, prefix: 'Saving · '),
      ),
    ));
  }

  testWidgets('a job over 30 seconds shows the time left after 3 seconds',
      (tester) async {
    final eta = RemainingTime(clock: () => now)..start();
    await pump(tester, eta, done: 0.01);
    expect(find.byKey(const Key('remaining_time')), findsNothing);

    now = now.add(const Duration(seconds: 4));
    await pump(tester, eta, done: 0.1);
    expect(find.text('Saving · 00:00:36 remaining'), findsOneWidget);
  });

  testWidgets('a job under 30 seconds shows nothing', (tester) async {
    final eta = RemainingTime(clock: () => now)..start();
    now = now.add(const Duration(seconds: 4));
    await pump(tester, eta, done: 0.5);
    expect(find.byKey(const Key('remaining_time')), findsNothing);
  });

  testWidgets('counts a typical duration down every second', (tester) async {
    final eta = RemainingTime(clock: () => now)..start();
    await pump(tester, eta, typical: const Duration(seconds: 50));
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Saving · 00:00:47 remaining'), findsOneWidget);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Saving · 00:00:45 remaining'), findsOneWidget);
  });

  testWidgets('nothing to go on: shows nothing', (tester) async {
    final eta = RemainingTime(clock: () => now)..start();
    now = now.add(const Duration(seconds: 30));
    await pump(tester, eta);
    expect(find.byKey(const Key('remaining_time')), findsNothing);
  });

  test('typical save time: same size, else scaled by pixels', () {
    final s = AppSettings.instance..resetForTest();
    addTearDown(s.resetForTest);
    expect(s.typicalSave(2160), isNull);
    s.saveMillis = {1080: 1000};
    expect(s.typicalSave(1080), const Duration(seconds: 1));
    expect(s.typicalSave(2160), const Duration(seconds: 4));

    final copy = s.toMap();
    s.resetForTest();
    s.applyMap(copy);
    expect(s.saveMillis, {1080: 1000});
  });
}
