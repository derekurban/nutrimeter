// Reading a label needs the person's API key, whichever way a reading would start: the photos screen, a retry, carrying
// on past a finding. Without one, the prompt to add a key, and nothing runs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimeter/data/label_review.dart';
import 'package:nutrimeter/data/store.dart';
import 'package:nutrimeter/services/label_pipeline.dart';
import 'package:nutrimeter/services/llm.dart';
import 'package:nutrimeter/services/reading_settings.dart';
import 'package:nutrimeter/services/submissions.dart';
import 'package:nutrimeter/ui/product_flow.dart';
import 'package:nutrimeter/ui/theme.dart';

const _id = 'b2c3d4e5-0000-4000-8000-000000000001';

PendingPhoto _photo(PhotoRole role, String c) =>
    PendingPhoto(role: role, file: 'submissions/$_id/${c * 64}.jpg', sha256: c * 64, contentType: 'image/jpeg', bytes: 1000);

LabelReview _review(ReviewStage stage, {String? error, String? finding}) => LabelReview(
      id: _id,
      provisionalId: 'pending:$_id',
      nameHint: 'Oat crackers',
      photos: [_photo(PhotoRole.front, 'a'), _photo(PhotoRole.nutrition, 'b')],
      stage: stage,
      error: error,
      finding: finding,
      findingRole: finding == null ? null : 'nutrition',
      createdAt: DateTime(2026, 11, 12),
    );

Future<AppState> _open(WidgetTester tester, LabelReview review) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final state = AppState.memory()..putReview(review);
  await tester.pumpWidget(AppScope(
    state: state,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: const ProductFlowPage(reviewId: _id)),
  ));
  await tester.pump();
  return state;
}

void main() {
  tearDown(() => ApiKeys.setForTest(const {}));

  testWidgets('the photos screen reads only with a key, and a key removed meanwhile takes the read away', (tester) async {
    ApiKeys.setForTest(const {LlmProvider.anthropic: 'sk-ant-test'});
    final state = await _open(tester, _review(ReviewStage.photos));
    expect(find.text('Read the label'), findsOneWidget);
    expect(find.text('Add an API key to read it here'), findsNothing);

    ApiKeys.setForTest(const {});
    await tester.pump();
    expect(find.text('Read the label'), findsNothing);
    expect(find.text('Add an API key to read it here'), findsOneWidget);
    expect(find.textContaining('desktop'), findsNothing);
    expect(state.labelReviews[_id]!.stage, ReviewStage.photos);
    await tester.pump(const Duration(seconds: 1)); // the pending save
  });

  testWidgets('trying a stopped reading again without a key asks for one and runs nothing', (tester) async {
    final state = await _open(tester, _review(ReviewStage.stopped, error: 'Interrupted when the app closed.'));
    expect(find.text('Stopped'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Reading needs an API key'), findsOneWidget);
    expect(find.text('Add an API key to read it here'), findsOneWidget);
    expect(LabelPipeline.isRunning(_id), isFalse);
    final r = state.labelReviews[_id]!;
    expect((r.stage, r.runs.length, r.error), (ReviewStage.stopped, 0, 'Interrupted when the app closed.'));

    // Dismissed, the review waits as it was.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Reading needs an API key'), findsNothing);
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('carrying on past a finding without a key asks for one and runs nothing', (tester) async {
    final state = await _open(tester, _review(ReviewStage.paused, finding: 'The table is cut off at the bottom.'));
    expect(find.text('The table is hard to read'), findsOneWidget);

    await tester.tap(find.text('Carry on'));
    await tester.pumpAndSettle();
    expect(find.text('Reading needs an API key'), findsOneWidget);
    expect(LabelPipeline.isRunning(_id), isFalse);
    final r = state.labelReviews[_id]!;
    expect((r.stage, r.carriedOn, r.finding), (ReviewStage.paused, false, 'The table is cut off at the bottom.'));

    // Retaking the table asks for the key before the photo is replaced.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake the table'));
    await tester.pumpAndSettle();
    expect(find.text('Reading needs an API key'), findsOneWidget);
    expect(state.labelReviews[_id]!.photos.map((p) => p.sha256.substring(0, 1)), ['a', 'b']);
  });
}
