import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/data/model.dart';
import 'package:nutrimeter/data/store.dart';
import 'package:nutrimeter/ui/app.dart';

void main() {
  testWidgets('log a custom food from the picker and see it in the diary', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final state = AppState.memory();
    state.saveCustomFood(const Food(
      id: 'custom:bar',
      source: FoodSource.custom,
      name: 'Protein bar',
      nutrients: {'energy': 400, 'protein': 33, 'carbs': 37, 'fat': 15},
      servings: [Serving('bar', 60)],
    ));
    await tester.pumpWidget(NutrimeterApp(state: state));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('0'), findsWidgets);

    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'protein');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protein bar').first);
    await tester.pumpAndSettle();
    expect(find.text('= 60 g'), findsOneWidget);

    await tester.tap(find.text('Add to diary'));
    await tester.pumpAndSettle();
    expect(state.entries.single.grams, 60);
    expect(find.text('Protein bar'), findsOneWidget);
    expect(find.text('240 kcal'), findsOneWidget);
  });
}
