// Runs a label review on the phone, step by step: the first read, the second read, the checks, and the verifier on
// whatever is still in doubt; later, one re-read for the person's notes. Every step is saved as soon as it finishes,
// so a closed app resumes where it stopped, and nothing is ever re-run unasked (each call costs the person money).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/label_review.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/label_reading.dart';
import 'llm.dart';
import 'reading_settings.dart';

class LabelPipeline {
  LabelPipeline._();

  static final _running = <String>{};

  /// Ids of reviews with a step running, for the UI.
  static final running = ValueNotifier<Set<String>>(const {});

  static bool isRunning(String id) => _running.contains(id);

  /// The categories, for the first read's turn and its schema.
  static List<({String id, String path})> categories(AppState state) {
    final t = state.taxonomy;
    return [
      for (final c in t.categories.values) (id: c.id, path: t.path(c.id).map((x) => x.name).join(' › ')),
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  static String categoryName(AppState state, String id) {
    final path = state.taxonomy.path(id);
    return path.isEmpty ? id : path.last.name;
  }

  /// The review's lines as they stand, with the checks applied.
  static ({List<ReviewLine> lines, List<LabelCheck> checks}) linesOf(AppState state, LabelReview r) {
    String name(String id) => categoryName(state, id);
    final draft = buildLines(r, categoryName: name, checks: const []);
    final checks = _checks(r, draft);
    return (lines: buildLines(r, categoryName: name, checks: checks), checks: checks);
  }

  static List<LabelCheck> _checks(LabelReview r, List<ReviewLine> lines) {
    final values = <String, double>{};
    for (final l in lines.where((l) => l.kind == 'nutrient' && l.amount != null)) {
      final key = l.id.substring(2);
      final def = nutrientByKey[key];
      final c = def == null ? null : convertUnit(l.amount!, l.unit, def.unit);
      if (c != null) values[key] = c;
    }
    final serving = lines.where((l) => l.id == 'serving').firstOrNull;
    final grams = serving == null ? null : parseServing(serving.value).grams ?? servingOf((r.firstRead?['table']?['serving'] as Map?)?.cast<String, dynamic>()).grams;
    return runChecks(
      first: r.firstRead,
      second: r.secondRead,
      values: values,
      servingGrams: grams,
      gtin: r.gtin,
      rawBarcode: r.rawBarcode,
      ingredientsPhotographed: r.photos.any((p) => p.role.name == 'ingredients'),
    );
  }

  /// The steps run since the latest first read (a retaken photo starts the reading over).
  static Iterable<StepRun> _since(LabelReview r) {
    final i = r.runs.lastIndexWhere((x) => x.kind == 'first-read' && x.status == 'done');
    return i < 0 ? const [] : r.runs.skip(i + 1);
  }

  static void _mark(String id, bool on) {
    on ? _running.add(id) : _running.remove(id);
    running.value = {..._running};
  }

  /// Runs every step not done yet, from wherever the review stands. Returns when it stops: ready for the person,
  /// paused on a finding, or stopped by an error.
  static Future<void> run(AppState state, String id) async {
    if (_running.contains(id)) return;
    _mark(id, true);
    try {
      await _run(state, id);
    } finally {
      _mark(id, false);
    }
  }

  static Future<void> _run(AppState state, String id) async {
    LabelReview? current() => state.labelReviews[id];
    var r = current();
    if (r == null) return;
    final keys = ApiKeys.present;
    if (keys.isEmpty) {
      state.putReview(r.copyWith(stage: ReviewStage.stopped, error: () => 'Add an Anthropic or OpenAI key under Targets → Label reading.'));
      return;
    }
    final settings = state.readingSettings;
    state.putReview(r = r.copyWith(stage: ReviewStage.reading, error: () => null));

    // 1. The first read.
    if (r.firstRead == null) {
      final choice = settings.choice(ReadingStep.firstRead, keys);
      final cats = categories(state);
      final answer = await _call(state, id, 'first-read', choice,
          system: firstReadSystem,
          text: firstReadText(r, cats),
          photos: r.orderedPhotos.map((p) => p.file).toList(),
          schema: firstReadSchema([for (final c in cats) c.id]),
          schemaName: 'label_reading',
          summarise: (j) {
            final n = (j['nutrients'] as List?)?.length ?? 0;
            final c = (j['caveats'] as List?)?.length ?? 0;
            return j['verdict'] == 'transcribed' ? '$n lines read${c == 0 ? '' : ', $c doubts noted'}' : 'Verdict: ${j['verdict']}';
          });
      if (answer == null) return;
      final checked = sanitizeFirstRead(answer, {for (final c in cats) c.id});
      r = current()!.copyWith(firstRead: () => checked, carriedOn: false);
      state.putReview(r);
    }

    // A finding the person should decide on.
    final finding = findingAfterFirstRead(r.firstRead!);
    if (finding != null && !r.carriedOn) {
      state.putReview(r.copyWith(stage: ReviewStage.paused, finding: () => finding.message, findingRole: () => finding.role));
      return;
    }
    if (r.firstRead!['verdict'] != 'transcribed') {
      state.putReview(r.copyWith(stage: ReviewStage.review, finding: () => null));
      return;
    }

    // 2. The second read, of the nutrition photo alone.
    final tablePhotos = r.orderedPhotos.where((p) => p.role.name == 'nutrition').map((p) => p.file).toList();
    if (r.secondRead == null && tablePhotos.isNotEmpty) {
      final choice = settings.choice(ReadingStep.secondRead, keys);
      final answer = await _call(state, id, 'second-read', choice,
          system: secondReadSystem,
          text: secondReadText(r.firstRead),
          photos: tablePhotos,
          schema: secondReadSchema,
          schemaName: 'table_reading',
          summarise: (j) => '${(j['nutrients'] as List?)?.length ?? 0} lines read');
      if (answer == null) return;
      r = current()!.copyWith(secondRead: () => sanitizeNutrientRows(answer));
      state.putReview(r);
    }

    // 3. The checks, on the phone.
    var view = linesOf(state, r);
    if (!_since(r).any((x) => x.kind == 'checks')) {
      final failed = view.checks.where((c) => c.level != 'ok').length;
      final passed = view.checks.where((c) => c.level == 'ok').length;
      final disagree = view.lines.where((l) => l.second != null && l.first != null && l.reasons.any((x) => x.startsWith('The two reads disagree'))).length;
      state.putReview(r = r.copyWith(runs: [
        ...r.runs,
        StepRun(
          kind: 'checks',
          status: 'done',
          startedAt: DateTime.now(),
          summary: [
            '$passed passed',
            if (failed > 0) '$failed to look at',
            if (disagree > 0) 'the reads differ on $disagree line${disagree == 1 ? '' : 's'}',
          ].join(', '),
        ),
      ]));
    }

    // 4. The verifier, only on what is in doubt.
    if (!r.verifier.any((v) => v['kind'] == 'escalation') && !_since(r).any((x) => x.kind == 'verifier')) {
      final doubtful = view.lines.where((l) => l.needsYou(settings.bar) && l.kind != 'category').toList();
      if (doubtful.isEmpty) {
        state.putReview(r = r.copyWith(runs: [
          ...r.runs,
          StepRun(kind: 'verifier', status: 'skipped', startedAt: DateTime.now(), summary: 'Nothing in doubt, so not needed'),
        ]));
      } else {
        final choice = settings.choice(ReadingStep.verifier, keys);
        final answer = await _call(state, id, 'verifier', choice,
            system: verifierSystem,
            text: verifierText(r, doubtful),
            photos: r.orderedPhotos.map((p) => p.file).toList(),
            schema: verifierSchema,
            schemaName: 'verification',
            summarise: (j) {
              final ls = ((j['lines'] as List?) ?? const []).cast<Map>();
              final sure = ls.where((l) => l['readable'] == true && l['confidence'] == 'high').length;
              return 'Looked again at ${doubtful.length} line${doubtful.length == 1 ? '' : 's'}: $sure settled';
            });
        if (answer == null) return;
        r = current()!.copyWith(verifier: [
          ...current()!.verifier,
          {'kind': 'escalation', 'ids': [for (final l in doubtful) l.id], 'answer': answer},
        ]);
        state.putReview(r);
      }
    }
    state.putReview(current()!.copyWith(stage: ReviewStage.review, finding: () => null));
  }

  /// Sends the person's notes to the verifier in one request, then goes back to the review.
  static Future<void> recheck(AppState state, String id) async {
    if (_running.contains(id)) return;
    _mark(id, true);
    try {
      var r = state.labelReviews[id];
      if (r == null) return;
      final notes = r.pendingNotes;
      if (notes.isEmpty) return;
      final keys = ApiKeys.present;
      if (keys.isEmpty) {
        state.putReview(r.copyWith(stage: ReviewStage.stopped, error: () => 'Add an Anthropic or OpenAI key under Targets → Label reading.'));
        return;
      }
      state.putReview(r = r.copyWith(stage: ReviewStage.rechecking, error: () => null));
      final lines = linesOf(state, r).lines.where((l) => notes.containsKey(l.id)).toList();
      final choice = state.readingSettings.choice(ReadingStep.verifier, keys);
      final cats = categories(state);
      final answer = await _call(state, id, 'recheck', choice,
          system: verifierSystem,
          text: verifierText(r, lines, notes: notes, categories: cats),
          photos: r.orderedPhotos.map((p) => p.file).toList(),
          schema: verifierSchema,
          schemaName: 'verification',
          summarise: (j) => 'Re-read ${notes.length} line${notes.length == 1 ? '' : 's'} with your notes');
      if (answer == null) return;
      r = state.labelReviews[id]!;
      state.putReview(r.copyWith(
        stage: ReviewStage.review,
        verifier: [...r.verifier, {'kind': 'notes', 'notes': notes, 'answer': sanitizeVerifier(answer, {for (final c in cats) c.id})}],
        rechecked: {...r.rechecked, ...notes},
        decisions: {for (final e in r.decisions.entries) if (!notes.containsKey(e.key)) e.key: e.value},
      ));
    } finally {
      _mark(id, false);
    }
  }

  /// One model call, recorded as a step. Returns the answer, or null after recording the failure and stopping.
  static Future<Map<String, dynamic>?> _call(
    AppState state,
    String id,
    String kind,
    StepChoice choice, {
    required String system,
    required String text,
    required List<String> photos,
    required Map<String, dynamic> schema,
    required String schemaName,
    required String Function(Map<String, dynamic>) summarise,
  }) async {
    var r = state.labelReviews[id]!;
    final run = StepRun(kind: kind, status: 'running', startedAt: DateTime.now(), provider: choice.provider.name, model: choice.model);
    final index = r.runs.length;
    state.putReview(r = r.copyWith(runs: [...r.runs, run]));
    void finishRun(StepRun done, {String? error, ReviewStage? stage}) {
      final now = state.labelReviews[id]!;
      final runs = [...now.runs];
      if (index < runs.length) runs[index] = done;
      state.putReview(now.copyWith(runs: runs, stage: stage, error: error == null ? null : () => error));
    }

    try {
      final dir = state.dataDir;
      final images = <LlmImage>[];
      for (final rel in photos) {
        final p = r.photos.firstWhere((x) => x.file == rel);
        final bytes = dir == null ? null : await File('${dir.path}/$rel').readAsBytes();
        if (bytes == null) throw const LlmException('A photo is missing from this phone.');
        images.add(LlmImage(bytes, p.contentType));
      }
      final key = ApiKeys.of(choice.provider) ?? (throw LlmException('No ${choice.provider.label} key.', keyProblem: true));
      LlmResult? result;
      for (var attempt = 1;; attempt++) {
        try {
          result = await callLlm(
            provider: choice.provider,
            apiKey: key,
            model: choice.model,
            effort: choice.effort,
            system: system,
            text: text,
            images: images,
            schema: schema,
            schemaName: schemaName,
          );
          break;
        } on LlmException catch (e) {
          if (!e.retryable || attempt >= 2) rethrow;
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
      final cost = result.costUsd;
      if (cost != null) state.addReadingSpend(cost);
      finishRun(run.copyWith(
        status: 'done',
        ms: result.ms,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        costUsd: cost,
        model: result.model,
        summary: summarise(result.json),
      ));
      return result.json;
    } catch (e) {
      final msg = e is LlmException ? e.message : '$e';
      debugPrint('Label reading, $kind: $msg');
      finishRun(run.copyWith(status: 'failed', ms: DateTime.now().difference(run.startedAt).inMilliseconds, error: msg), error: msg, stage: ReviewStage.stopped);
      return null;
    }
  }
}
