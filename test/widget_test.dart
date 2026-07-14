import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
  }

  Future<void> openQuickStartMode(
    WidgetTester tester,
    String title,
  ) async {
    await tester.tap(find.text('Quick Start'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> expectConfigLabelVisible(
    WidgetTester tester,
    String label,
  ) async {
    final finder = find.text(label);
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(finder, findsOneWidget);
  }

  testWidgets('Workout timer opens from timer button', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();

    expect(find.text('Session Builder'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VO2max quick start opens workout page', (WidgetTester tester) async {
    await pumpApp(tester);

    await openQuickStartMode(tester, 'VO2max 4x4 (Quick Start)');

    expect(find.text('Session Builder'), findsOneWidget);
    await expectConfigLabelVisible(tester, 'Work: 240s');
    await expectConfigLabelVisible(tester, 'Warmup: 600s');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calisthenics quick start opens workout page', (WidgetTester tester) async {
    await pumpApp(tester);

    await openQuickStartMode(tester, 'Calisthenics');

    expect(find.text('Session Builder'), findsOneWidget);
    await expectConfigLabelVisible(tester, 'Work: 40s');
    await expectConfigLabelVisible(tester, 'Warmup: 120s');
    expect(tester.takeException(), isNull);
  });
}
