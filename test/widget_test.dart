import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';

void main() {
  testWidgets('Workout timer screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Immersive Workout Timer'), findsOneWidget);
    expect(find.text('Session Builder'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
  });
}
