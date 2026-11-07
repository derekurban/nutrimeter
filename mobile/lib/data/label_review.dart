// A product being added from its label on this phone, from the photos to the published record. Everything the
// pipeline produced is kept here as it came (each model call, each reading, each check), together with the person's
// decisions, so the review survives restarts, can be resumed at any step, and travels to the backend as evidence.
import '../services/submissions.dart';

/// Where a review is.
enum ReviewStage {
  /// Photos are being taken; nothing has been read.
  photos,

  /// The pipeline is running.
  reading,

  /// The pipeline stopped on something the person should decide (a photo that is hard to read, say).
  paused,

  /// A step failed; it can be retried.
  stopped,

  /// Readings are ready for the person.
  review,

  /// The person's notes are being re-read.
  rechecking,

  /// The person accepted it; the record is on the phone and is published when signed in.
  accepted,
}

/// One model call or local step, for the trail and the cost.
class StepRun {
  const StepRun({
    required this.kind,
    required this.status,
    required this.startedAt,
    this.provider,
    this.model,
    this.ms,
    this.inputTokens,
    this.outputTokens,
    this.costUsd,
    this.summary,
    this.error,
  });

  /// `first-read`, `second-read`, `checks`, `verifier` or `recheck`.
  final String kind;

  /// `running`, `done`, `failed` or `skipped`.
  final String status;
  final DateTime startedAt;
  final String? provider;
  final String? model;
  final int? ms;
  final int? inputTokens;
  final int? outputTokens;
  final double? costUsd;

  /// One line on what came out of it.
  final String? summary;
  final String? error;

  StepRun copyWith({String? status, int? ms, int? inputTokens, int? outputTokens, double? costUsd, String? summary, String? error, String? model}) =>
      StepRun(
        kind: kind,
        status: status ?? this.status,
        startedAt: startedAt,
        provider: provider,
        model: model ?? this.model,
        ms: ms ?? this.ms,
        inputTokens: inputTokens ?? this.inputTokens,
        outputTokens: outputTokens ?? this.outputTokens,
        costUsd: costUsd ?? this.costUsd,
        summary: summary ?? this.summary,
        error: error ?? this.error,
      );

  Map<String, Object?> toJson() => {
        'kind': kind,
        'status': status,
        'startedAt': startedAt.toIso8601String(),
        'provider': ?provider,
        'model': ?model,
        'ms': ?ms,
        'inputTokens': ?inputTokens,
        'outputTokens': ?outputTokens,
        'costUsd': ?costUsd,
        'summary': ?summary,
        'error': ?error,
      };

  factory StepRun.fromJson(Map<String, dynamic> j) => StepRun(
        kind: j['kind'] as String,
        status: j['status'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        provider: j['provider'] as String?,
        model: j['model'] as String?,
        ms: (j['ms'] as num?)?.toInt(),
        inputTokens: (j['inputTokens'] as num?)?.toInt(),
        outputTokens: (j['outputTokens'] as num?)?.toInt(),
        costUsd: (j['costUsd'] as num?)?.toDouble(),
        summary: j['summary'] as String?,
        error: j['error'] as String?,
      );
}

/// What the person did with one line.
class LineDecision {
  const LineDecision({required this.kind, this.value, this.note, required this.at});

  /// `confirmed` (looks right), `chose` (picked one of the readings), `typed` (entered it), or `note` (asked the
  /// verifier to look again, with [note]).
  final String kind;

  /// The value they chose or typed, as text in the line's own terms ("3 g", "1 tbsp (15 g)", a category id).
  final String? value;
  final String? note;
  final DateTime at;

  Map<String, Object?> toJson() => {'kind': kind, 'value': ?value, 'note': ?note, 'at': at.toIso8601String()};

  factory LineDecision.fromJson(Map<String, dynamic> j) =>
      LineDecision(kind: j['kind'] as String, value: j['value'] as String?, note: j['note'] as String?, at: DateTime.parse(j['at'] as String));
}

class LabelReview {
  const LabelReview({
    required this.id,
    required this.provisionalId,
    this.rawBarcode,
    this.symbology,
    this.gtin,
    this.nameHint,
    this.note,
    this.photos = const [],
    this.stage = ReviewStage.photos,
    this.finding,
    this.findingRole,
    this.carriedOn = false,
    this.error,
    this.runs = const [],
    this.firstRead,
    this.secondRead,
    this.verifier = const [],
    this.decisions = const {},
    this.rechecked = const {},
    required this.createdAt,
    this.acceptedAt,
    this.recordId,
    this.categoryId,
    this.record,
    this.published = false,
    this.uploaded = false,
    this.publishError,
  });

  /// The submission's id, minted here.
  final String id;

  /// The food id the diary uses meanwhile: `gtin:<14>` or `pending:<uuid>`.
  final String provisionalId;
  final String? rawBarcode;
  final String? symbology;
  final String? gtin;
  final String? nameHint;

  /// Anything the person told the reader before it read.
  final String? note;

  /// Front, nutrition table, ingredients, others: kept in `submissions/<id>/`.
  final List<PendingPhoto> photos;
  final ReviewStage stage;

  /// Why the pipeline paused, in a sentence, and the photo a retake would replace.
  final String? finding;
  final String? findingRole;

  /// The person chose to carry on past a finding.
  final bool carriedOn;

  /// Why the last step failed.
  final String? error;
  final List<StepRun> runs;

  /// The first read's answer, the second read's, and every verifier answer (the escalation, then one per batch of
  /// notes), each as the model gave it.
  final Map<String, dynamic>? firstRead;
  final Map<String, dynamic>? secondRead;
  final List<Map<String, dynamic>> verifier;

  /// Line id → what the person did.
  final Map<String, LineDecision> decisions;

  /// Line id → the note the verifier re-read it for (kept after the note itself is answered).
  final Map<String, String> rechecked;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  /// What was accepted: the record id, its category and the record's data as published.
  final String? recordId;
  final String? categoryId;
  final Map<String, dynamic>? record;

  /// The submission and its photos are uploaded, and the record is published.
  final bool uploaded;
  final bool published;
  final String? publishError;

  /// Photos in the order they are sent to the models: front, nutrition, ingredients, others.
  List<PendingPhoto> get orderedPhotos => [...photos]..sort((a, b) => a.role.index.compareTo(b.role.index));

  double get costUsd => runs.fold(0.0, (a, r) => a + (r.costUsd ?? 0));

  bool get costKnown => runs.every((r) => r.costUsd != null || r.inputTokens == null);

  /// Notes waiting to be sent to the verifier.
  Map<String, String> get pendingNotes => {
        for (final e in decisions.entries)
          if (e.value.kind == 'note' && (e.value.note?.isNotEmpty ?? false)) e.key: e.value.note!,
      };

  String get displayName => (record?['name'] as String?) ?? (firstRead?['front']?['name'] as String?)?.nonEmpty ?? nameHint ?? 'New product';

  LabelReview copyWith({
    List<PendingPhoto>? photos,
    String? Function()? note,
    ReviewStage? stage,
    String? Function()? finding,
    String? Function()? findingRole,
    bool? carriedOn,
    String? Function()? error,
    List<StepRun>? runs,
    Map<String, dynamic>? Function()? firstRead,
    Map<String, dynamic>? Function()? secondRead,
    List<Map<String, dynamic>>? verifier,
    Map<String, LineDecision>? decisions,
    Map<String, String>? rechecked,
    DateTime? acceptedAt,
    String? recordId,
    String? Function()? categoryId,
    Map<String, dynamic>? record,
    bool? uploaded,
    bool? published,
    String? Function()? publishError,
  }) =>
      LabelReview(
        id: id,
        provisionalId: provisionalId,
        rawBarcode: rawBarcode,
        symbology: symbology,
        gtin: gtin,
        nameHint: nameHint,
        note: note != null ? note() : this.note,
        photos: photos ?? this.photos,
        stage: stage ?? this.stage,
        finding: finding != null ? finding() : this.finding,
        findingRole: findingRole != null ? findingRole() : this.findingRole,
        carriedOn: carriedOn ?? this.carriedOn,
        error: error != null ? error() : this.error,
        runs: runs ?? this.runs,
        firstRead: firstRead != null ? firstRead() : this.firstRead,
        secondRead: secondRead != null ? secondRead() : this.secondRead,
        verifier: verifier ?? this.verifier,
        decisions: decisions ?? this.decisions,
        rechecked: rechecked ?? this.rechecked,
        createdAt: createdAt,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        recordId: recordId ?? this.recordId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        record: record ?? this.record,
        uploaded: uploaded ?? this.uploaded,
        published: published ?? this.published,
        publishError: publishError != null ? publishError() : this.publishError,
      );

  /// The submission row the backend gets (as for a desktop review, but never queued).
  PendingSubmission get submission => PendingSubmission(
        id: id,
        provisionalId: provisionalId,
        rawBarcode: rawBarcode,
        symbology: symbology,
        gtin: gtin,
        nameHint: nameHint,
        note: note,
        photos: photos,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'provisionalId': provisionalId,
        'rawBarcode': ?rawBarcode,
        'symbology': ?symbology,
        'gtin': ?gtin,
        'nameHint': ?nameHint,
        'note': ?note,
        'photos': [for (final p in photos) p.toJson()],
        'stage': stage.name,
        'finding': ?finding,
        'findingRole': ?findingRole,
        if (carriedOn) 'carriedOn': true,
        'error': ?error,
        'runs': [for (final r in runs) r.toJson()],
        'firstRead': ?firstRead,
        'secondRead': ?secondRead,
        'verifier': verifier,
        'decisions': {for (final e in decisions.entries) e.key: e.value.toJson()},
        'rechecked': rechecked,
        'createdAt': createdAt.toIso8601String(),
        'acceptedAt': ?acceptedAt?.toIso8601String(),
        'recordId': ?recordId,
        'categoryId': ?categoryId,
        'record': ?record,
        if (uploaded) 'uploaded': true,
        if (published) 'published': true,
        'publishError': ?publishError,
      };

  factory LabelReview.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
    final runs = [for (final r in (j['runs'] as List? ?? const [])) StepRun.fromJson((r as Map).cast<String, dynamic>())];
    var stage = ReviewStage.values.where((s) => s.name == j['stage']).firstOrNull ?? ReviewStage.photos;
    // A step that was running when the app was closed did not finish: it can be resumed.
    final interrupted = runs.any((r) => r.status == 'running');
    if (stage == ReviewStage.reading || stage == ReviewStage.rechecking || interrupted) stage = ReviewStage.stopped;
    return LabelReview(
      id: j['id'] as String,
      provisionalId: j['provisionalId'] as String,
      rawBarcode: j['rawBarcode'] as String?,
      symbology: j['symbology'] as String?,
      gtin: j['gtin'] as String?,
      nameHint: j['nameHint'] as String?,
      note: j['note'] as String?,
      photos: [for (final p in (j['photos'] as List? ?? const [])) PendingPhoto.fromJson((p as Map).cast<String, dynamic>())],
      stage: stage,
      finding: j['finding'] as String?,
      findingRole: j['findingRole'] as String?,
      carriedOn: j['carriedOn'] as bool? ?? false,
      error: interrupted && j['error'] == null ? 'Interrupted when the app closed.' : j['error'] as String?,
      runs: [for (final r in runs) r.status == 'running' ? r.copyWith(status: 'failed', error: 'Interrupted') : r],
      firstRead: map(j['firstRead']),
      secondRead: map(j['secondRead']),
      verifier: [for (final v in (j['verifier'] as List? ?? const [])) if (v is Map) v.cast<String, dynamic>()],
      decisions: {
        for (final e in ((j['decisions'] as Map?) ?? const {}).entries) e.key as String: LineDecision.fromJson((e.value as Map).cast<String, dynamic>()),
      },
      rechecked: {for (final e in ((j['rechecked'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
      createdAt: DateTime.parse(j['createdAt'] as String),
      acceptedAt: j['acceptedAt'] is String ? DateTime.parse(j['acceptedAt'] as String) : null,
      recordId: j['recordId'] as String?,
      categoryId: j['categoryId'] as String?,
      record: map(j['record']),
      uploaded: j['uploaded'] as bool? ?? false,
      published: j['published'] as bool? ?? false,
      publishError: j['publishError'] as String?,
    );
  }
}

extension NonEmpty on String {
  String? get nonEmpty => trim().isEmpty ? null : trim();
}
