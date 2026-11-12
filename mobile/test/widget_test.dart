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

  testWidgets('a search miss is a new find, read from the label', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final state = AppState.memory();
    await tester.pumpWidget(NutrimeterApp(state: state));
    await tester.tap(find.text('Log food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'zzqx crackers');
    await tester.pumpAndSettle();
    expect(find.text('Add a product'), findsOneWidget);

    await tester.tap(find.text('Add a product'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('You found something new'), findsOneWidget);
    expect(find.text('“zzqx crackers”'), findsOneWidget);
    // Nothing else is offered: no logging by weight, no generic instead.
    expect(find.textContaining('weight'), findsNothing);

    await tester.tap(find.text('Add it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Photograph the label'), findsOneWidget);
    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Nutrition table'), findsOneWidget);
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Optional, worth it'), findsOneWidget);
    expect(state.labelReviews.values.single.nameHint, 'zzqx crackers');
    // Without a key the only way forward is to add one: the label is read nowhere else.
    expect(find.text('Add an API key to read it here'), findsOneWidget);
    expect(find.text('Read the label'), findsNothing);
    expect(find.textContaining('desktop'), findsNothing);

    // Leaving with no photos forgets it.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.labelReviews, isEmpty);
  });
}
