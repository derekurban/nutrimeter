// Adding a product nobody has read yet, from the moment a scan or search finds nothing to the product page where it
// is logged: the new-find moment, the label photos, the reading (watchable, or left to run), the review against the
// photos, and acceptance. One route follows the review's stage, so the flow can be left and picked up again anywhere.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/label_review.dart';
import '../data/model.dart';
import '../data/store.dart';
import '../logic/barcode.dart';
import '../logic/label_reading.dart';
import '../services/backend.dart';
import '../services/label_pipeline.dart';
import '../services/llm.dart';
import '../services/reading_settings.dart';
import '../services/submissions.dart';
import 'food_detail.dart';
import 'label_review_screen.dart';
import 'reading_settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the flow for a new product ([barcode] or [nameHint]) or for a review already under way ([reviewId]).
/// Returns the accepted product (or, sent to the desktop instead, its provisional food); null if left.
Future<Food?> openProductFlow(BuildContext context, {Gtin? barcode, String? nameHint, String? reviewId}) => Navigator.of(context)
    .push<Food>(MaterialPageRoute(builder: (_) => ProductFlowPage(barcode: barcode, nameHint: nameHint, reviewId: reviewId)));

/// Picks a review up where it stands (from the diary or the list of added products); once it is accepted, opens the
/// product to log it on [date] (today by default).
Future<void> resumeReview(BuildContext context, LabelReview review, {String? date, Meal? meal}) async {
  final state = AppScope.read(context);
  final food = await openProductFlow(context, reviewId: review.id);
  if (food == null || !context.mounted) return;
  final m = meal ?? MealLabel.forTime(DateTime.now());
  final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
    builder: (_) => FoodDetailPage(food: food, actionLabel: 'Add to diary', meal: m, justAdded: food.source == FoodSource.catalogue),
  ));
  if (result == null || !context.mounted) return;
  state.log(date: date ?? isoDate(DateTime.now()), meal: result.meal ?? m, food: result.food, quantity: result.quantity, unit: result.unit);
  showToast(context, 'Added ${result.food.name} to ${(result.meal ?? m).label}');
}

class ProductFlowPage extends StatefulWidget {
  const ProductFlowPage({super.key, this.barcode, this.nameHint, this.reviewId});

  final Gtin? barcode;
  final String? nameHint;
  final String? reviewId;

  @override
  State<ProductFlowPage> createState() => _ProductFlowPageState();
}

class _ProductFlowPageState extends State<ProductFlowPage> {
  late String? _id = widget.reviewId;

  /// The reading was watched in this visit, so its verdict is shown before the review opens.
  bool _watched = false;
  final _picker = ImagePicker();

  void _start() {
    final state = AppScope.read(context);
    final id = uuidV4();
    final code = widget.barcode;
    state.putReview(LabelReview(
      id: id,
      provisionalId: code?.id ?? 'pending:$id',
      rawBarcode: code?.raw,
      symbology: code?.symbology.name,
      gtin: code?.gtin14,
      nameHint: widget.nameHint?.trim().nonEmpty,
      createdAt: DateTime.now(),
    ));
    setState(() => _id = id);
  }

  /// Takes a photo for [role] and keeps it with the review, replacing the one it had.
  Future<bool> _photo(PhotoRole role, ImageSource source) async {
    final state = AppScope.read(context);
    final id = _id;
    final dir = state.dataDir;
    if (id == null) return false;
    XFile? x;
    try {
      x = await _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 88);
    } catch (e) {
      if (mounted) showToast(context, 'Could not open the ${source == ImageSource.camera ? 'camera' : 'photos'}: $e');
      return false;
    }
    if (x == null || dir == null) return false;
    try {
      final p = await storePhoto(bytes: await x.readAsBytes(), role: role, dataDir: dir, submissionId: id);
      final r = state.labelReviews[id];
      if (r == null) return false;
      state.putReview(r.copyWith(photos: [
        for (final q in r.photos)
          if (q.role != role || role == PhotoRole.other) q,
        p,
      ]));
      return true;
    } catch (e) {
      if (mounted) showToast(context, 'Could not keep the photo: $e');
      return false;
    }
  }

  void _read() {
    final state = AppScope.read(context);
    final r = state.labelReviews[_id];
    if (r == null) return;
    state.putReview(r.copyWith(stage: ReviewStage.reading));
    setState(() => _watched = true);
    unawaited(LabelPipeline.run(state, r.id));
  }

  /// A retaken photo starts the reading over.
  Future<void> _retake(String role) async {
    final pr = PhotoRole.values.where((p) => p.name == role).firstOrNull ?? PhotoRole.nutrition;
    if (!await _photo(pr, ImageSource.camera) || !mounted) return;
    final state = AppScope.read(context);
    final r = state.labelReviews[_id]!;
    state.putReview(r.copyWith(
      firstRead: () => null,
      secondRead: () => null,
      verifier: const [],
      decisions: const {},
      rechecked: const {},
      carriedOn: false,
      finding: () => null,
      findingRole: () => null,
    ));
    _read();
  }

  /// Reads the whole label again from the same photos.
  void _reread() {
    final state = AppScope.read(context);
    final r = state.labelReviews[_id];
    if (r == null) return;
    state.putReview(r.copyWith(
      firstRead: () => null,
      secondRead: () => null,
      verifier: const [],
      decisions: const {},
      rechecked: const {},
      carriedOn: false,
      finding: () => null,
      findingRole: () => null,
    ));
    _read();
  }

  void _carryOn() {
    final state = AppScope.read(context);
    final r = state.labelReviews[_id]!;
    state.putReview(r.copyWith(carriedOn: true, finding: () => null));
    setState(() => _watched = true);
    unawaited(LabelPipeline.run(state, r.id));
  }

  /// The old way, for a phone without a key: the photos go to the desktop's review queue, and the product is logged by
  /// weight meanwhile.
  Future<void> _sendToDesktop() async {
    final state = AppScope.read(context);
    final r = state.labelReviews[_id];
    if (r == null) return;
    final food = Food(
      id: r.provisionalId,
      source: FoodSource.provisional,
      name: r.nameHint ?? 'New product',
      barcode: r.gtin,
      nutrients: const {},
    );
    state.addSubmission(r.submission, food);
    state.removeReview(r.id, deletePhotos: false);
    await state.save();
    unawaited(Backend.uploadPending(state));
    if (!mounted) return;
    showToast(context, Backend.account.value != null ? 'Sent for review on the desktop.' : 'Kept on this phone. Sign in under Targets → Food review to send it.');
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = _id == null ? null : state.labelReviews[_id];
    if (r == null) {
      return _NewFind(barcode: widget.barcode, nameHint: widget.nameHint, onAdd: _start);
    }
    return switch (r.stage) {
      ReviewStage.photos => _Capture(review: r, onPhoto: _photo, onRead: _read, onDesktop: _sendToDesktop),
      ReviewStage.review when !_watched => LabelReviewScreen(review: r, onRetake: _retake, onReread: _reread),
      ReviewStage.accepted => _Accepted(review: r),
      _ => _Reading(
          review: r,
          onRetake: _retake,
          onCarryOn: _carryOn,
          onRetry: () {
            setState(() => _watched = true);
            final run = r.pendingNotes.isNotEmpty && r.firstRead != null && r.secondRead != null ? LabelPipeline.recheck : LabelPipeline.run;
            unawaited(run(state, r.id));
          },
          onReview: () => setState(() => _watched = false),
        ),
    };
  }
}

// ── The new find ───────────────────────────────────────────────────────────────────────────────────────────────

class _NewFind extends StatefulWidget {
  const _NewFind({required this.barcode, required this.nameHint, required this.onAdd});

  final Gtin? barcode;
  final String? nameHint;
  final VoidCallback onAdd;

  @override
  State<_NewFind> createState() => _NewFindState();
}

class _NewFindState extends State<_NewFind> with SingleTickerProviderStateMixin {
  late final _twinkle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  Widget _sparkle(double size, double delay) => AnimatedBuilder(
        animation: _twinkle,
        builder: (context, _) {
          final reduce = MediaQuery.disableAnimationsOf(context);
          final t = ((_twinkle.value + delay) % 1.0);
          final s = reduce ? 1.0 : 0.4 + 0.6 * (1 - (2 * t - 1).abs());
          return Opacity(opacity: s, child: Transform.scale(scale: s, child: Icon(LucideIcons.sparkle, size: size, color: context.du.accentStrong)));
        },
      );

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final code = widget.barcode;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: du.accentSubtle, shape: BoxShape.circle, border: Border.all(color: du.accentLine)),
                  child: Icon(LucideIcons.package, size: 42, color: du.accentStrong),
                ),
                Positioned(top: 2, right: 10, child: _sparkle(14, 0.2)),
                Positioned(bottom: 10, left: 0, child: _sparkle(12, 0.55)),
                Positioned(top: 34, right: -4, child: _sparkle(9, 0.8)),
              ]),
            ),
            const SizedBox(height: 18),
            Text(code?.raw ?? '“${widget.nameHint ?? 'New product'}”',
                style: TextStyle(color: du.inkTertiary, fontSize: 13, letterSpacing: 0.6, fontFeatures: tabular)),
            const SizedBox(height: 8),
            Text('You found something new', textAlign: TextAlign.center, style: context.text.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Nobody has read this label yet. Two photos and a short read, and it is in the catalogue for good, '
              'with its numbers traced to your pictures.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted),
            ),
            const SizedBox(height: 8),
            Text('About two minutes. You can leave while it reads.', textAlign: TextAlign.center, style: TextStyle(color: du.inkTertiary, fontSize: 13)),
          ]),
        ),
      ),
      bottomNavigationBar: _Bar(children: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: widget.onAdd, child: const Text('Add it'))),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: context.du.surface, border: Border(top: BorderSide(color: context.du.line, width: 0.6))),
        child: SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Row(children: children)),
        ),
      );
}

// ── Photos ─────────────────────────────────────────────────────────────────────────────────────────────────────

class _Capture extends StatefulWidget {
  const _Capture({required this.review, required this.onPhoto, required this.onRead, required this.onDesktop});

  final LabelReview review;
  final Future<bool> Function(PhotoRole, ImageSource) onPhoto;
  final VoidCallback onRead;
  final VoidCallback onDesktop;

  @override
  State<_Capture> createState() => _CaptureState();
}

class _CaptureState extends State<_Capture> {
  late final _note = TextEditingController(text: widget.review.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  PendingPhoto? _of(PhotoRole role) => widget.review.photos.where((p) => p.role == role).lastOrNull;

  Future<void> _leave() async {
    final state = AppScope.read(context);
    final r = widget.review;
    if (r.photos.isEmpty) {
      state.removeReview(r.id);
    } else {
      state.putReview(r.copyWith(note: () => _note.text.trim().nonEmpty));
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _keepNote() {
    final state = AppScope.read(context);
    final r = state.labelReviews[widget.review.id];
    if (r != null) state.putReview(r.copyWith(note: () => _note.text.trim().nonEmpty));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final ready = _of(PhotoRole.front) != null && _of(PhotoRole.nutrition) != null;
    final state = AppScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Photograph the label'),
          leading: IconButton(icon: const Icon(LucideIcons.chevronLeft), tooltip: 'Back', onPressed: _leave),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          if (r.rawBarcode != null) Text(r.rawBarcode!, style: TextStyle(color: context.du.inkTertiary, fontSize: 13, fontFeatures: tabular)),
          const SizedBox(height: 6),
          Text('Fill the frame, keep the table flat, avoid glare. The reading works only from what you give it.', style: TextStyle(color: context.muted)),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (role, label, hint) in [
              (PhotoRole.front, 'Front', 'Name and size'),
              (PhotoRole.nutrition, 'Nutrition table', 'The whole table'),
              (PhotoRole.ingredients, 'Ingredients', 'Optional, worth it'),
            ]) ...[
              if (role != PhotoRole.front) const SizedBox(width: 10),
              Expanded(child: _Slot(label: label, hint: hint, photo: _of(role), dataDir: state.dataDir, onTake: (s) => widget.onPhoto(role, s))),
            ],
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Anything the reader should know?', hintText: 'e.g. this is the 2 kg jar'),
            onChanged: (_) => _keepNote(),
          ),
          const SizedBox(height: 12),
          Text('Photos stay on this phone and in your private review trail. They are never shown on the product.',
              style: TextStyle(color: context.du.inkTertiary, fontSize: 12.5)),
        ]),
        bottomNavigationBar: ValueListenableBuilder(
          valueListenable: ApiKeys.keys,
          builder: (context, keys, _) => _Bar(children: [
            if (keys.isEmpty) ...[
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilledButton.icon(
                    icon: const Icon(LucideIcons.keyRound, size: 18),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadingSettingsPage())),
                    label: const Text('Add an API key to read it here'),
                  ),
                  TextButton(onPressed: ready ? widget.onDesktop : null, child: const Text('Send it to the desktop review instead')),
                ]),
              ),
            ] else
              Expanded(
                child: FilledButton(
                  onPressed: ready
                      ? () {
                          _keepNote();
                          widget.onRead();
                        }
                      : null,
                  child: Text(ready ? 'Read the label' : 'Add the front and the nutrition table'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.label, required this.hint, required this.photo, required this.dataDir, required this.onTake});

  final String label;
  final String hint;
  final PendingPhoto? photo;
  final Directory? dataDir;
  final Future<bool> Function(ImageSource) onTake;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final p = photo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 3 / 4,
        child: Material(
          color: du.sunk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p == null ? du.lineStrong : du.accentLine, width: p == null ? 0.8 : 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTake(ImageSource.camera),
            child: Stack(fit: StackFit.expand, children: [
              if (p != null && dataDir != null)
                PhotoFile(dataDir: dataDir!, photo: p, fit: BoxFit.cover, cacheWidth: 360)
              else
                Center(child: Icon(LucideIcons.camera, color: du.inkSecondary, size: 26)),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Choose from photos',
                  style: IconButton.styleFrom(backgroundColor: du.surface.withValues(alpha: 0.85)),
                  icon: Icon(LucideIcons.image, size: 16, color: du.ink),
                  onPressed: () => onTake(ImageSource.gallery),
                ),
              ),
              if (p != null)
                Positioned(left: 6, bottom: 6, child: Icon(LucideIcons.circleCheck, size: 18, color: du.accentStrong)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: context.text.labelLarge),
      Text(p == null ? hint : 'Tap to retake', style: TextStyle(color: context.muted, fontSize: 12)),
    ]);
  }
}

// ── Reading ────────────────────────────────────────────────────────────────────────────────────────────────────

class _Reading extends StatelessWidget {
  const _Reading({required this.review, required this.onRetake, required this.onCarryOn, required this.onRetry, required this.onReview});

  final LabelReview review;
  final Future<void> Function(String role) onRetake;
  final VoidCallback onCarryOn;
  final VoidCallback onRetry;
  final VoidCallback onReview;

  static const _steps = [
    ('first-read', 'First read', 'Every line of the package, as printed'),
    ('second-read', 'Second read', 'The table again, without seeing the first read'),
    ('checks', 'Compared and checked', 'The two reads side by side, and the arithmetic'),
    ('verifier', 'Verifier', 'A stronger model looks again at what is in doubt'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = review;
    final du = context.du;
    final rechecking = r.stage == ReviewStage.rechecking || (r.stage == ReviewStage.stopped && r.runs.lastOrNull?.kind == 'recheck');
    final lastFirst = r.runs.lastIndexWhere((x) => x.kind == 'first-read');
    StepRun? runOf(String kind) {
      if (kind == 'first-read') return lastFirst < 0 ? null : r.runs[lastFirst];
      return r.runs.skip(lastFirst < 0 ? 0 : lastFirst).where((x) => x.kind == kind).lastOrNull;
    }

    final view = r.firstRead == null ? null : LabelPipeline.linesOf(state, r);
    final conf = view == null || r.stage != ReviewStage.review ? null : overallConfidence(view.lines);
    final bar = state.readingSettings.bar;
    final open = view?.lines.where((l) => l.needsYou(bar)).length ?? 0;
    final steps = rechecking ? [('recheck', 'Your notes', 'The verifier re-reads the lines you wrote about')] : _steps;
    final running = r.stage == ReviewStage.reading || r.stage == ReviewStage.rechecking;
    return Scaffold(
      appBar: AppBar(
        title: Text(rechecking ? 'Reading your notes' : r.stage == ReviewStage.review ? 'Read' : 'Reading the label'),
        actions: [
          if (conf != null) Padding(padding: const EdgeInsets.only(right: 16), child: ConfidenceChip(conf, bar: bar)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(r.displayName, style: context.text.titleMedium),
        if (r.rawBarcode != null) Text(r.rawBarcode!, style: TextStyle(color: du.inkTertiary, fontSize: 12.5, fontFeatures: tabular)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const Divider(),
                _Rung(title: steps[i].$2, detail: steps[i].$3, run: runOf(steps[i].$1), active: running && runOf(steps[i].$1) == null && _isNext(steps, i, runOf)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${r.costKnown ? '' : 'at least '}${formatUsd(r.costUsd)} so far', style: TextStyle(color: du.inkTertiary, fontSize: 12.5, fontFeatures: tabular)),
        ),
        if (r.stage == ReviewStage.paused && r.finding != null) ...[
          const SizedBox(height: 12),
          _Notice(
            tone: _Tone.warning,
            title: r.findingRole == 'nutrition' ? 'The table is hard to read' : 'Worth a look before going on',
            body: r.finding!,
            actions: [
              OutlinedButton(onPressed: () => onRetake(r.findingRole ?? 'nutrition'), child: Text('Retake the ${r.findingRole == 'front' ? 'front' : 'table'}')),
              FilledButton(onPressed: onCarryOn, child: const Text('Carry on')),
            ],
          ),
        ],
        if (r.stage == ReviewStage.stopped) ...[
          const SizedBox(height: 12),
          _Notice(
            tone: _Tone.danger,
            title: 'Stopped',
            body: r.error ?? 'A step did not finish.',
            actions: [
              if ((r.error ?? '').contains('key'))
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadingSettingsPage())),
                  child: const Text('Label reading settings'),
                ),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ],
        if (conf != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$conf%', style: context.text.headlineLarge?.copyWith(fontFeatures: tabular)),
                  TextSpan(text: '  confident', style: TextStyle(color: context.muted)),
                ])),
                const SizedBox(height: 6),
                Text(
                  r.firstRead?['verdict'] != 'transcribed'
                      ? 'No nutrition table could be read. Retake the photo of the table, or look at what was read.'
                      : open == 0
                          ? 'Nothing needs you. The review opens on the whole record for a last look before you accept it.'
                          : '$open line${open == 1 ? '' : 's'} under your $bar% bar. The review opens on just ${open == 1 ? 'that one' : 'those'}; the rest is marked off.',
                  style: TextStyle(color: context.muted),
                ),
              ]),
            ),
          ),
        ],
        if (running) ...[
          const SizedBox(height: 14),
          Text('You can go back to the diary. This carries on while the app is open, and the product waits for you there.',
              style: TextStyle(color: context.muted, fontSize: 13)),
        ],
      ]),
      bottomNavigationBar: _Bar(children: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to diary')),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: r.stage == ReviewStage.review ? onReview : null, child: const Text('Review'))),
      ]),
    );
  }

  static bool _isNext(List<(String, String, String)> steps, int i, StepRun? Function(String) runOf) {
    for (var j = 0; j < i; j++) {
      final run = runOf(steps[j].$1);
      if (run == null || run.status == 'running' || run.status == 'failed') return false;
    }
    return true;
  }
}

class _Rung extends StatelessWidget {
  const _Rung({required this.title, required this.detail, required this.run, required this.active});

  final String title;
  final String detail;
  final StepRun? run;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final r = run;
    final status = r?.status ?? (active ? 'running' : 'pending');
    final icon = switch (status) {
      'running' => SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: du.accentStrong)),
      'done' => Icon(LucideIcons.circleCheck, size: 20, color: du.accentStrong),
      'failed' => Icon(LucideIcons.circleX, size: 20, color: du.danger),
      'skipped' => Icon(LucideIcons.circleMinus, size: 20, color: du.inkTertiary),
      _ => Icon(LucideIcons.circle, size: 20, color: du.lineStrong),
    };
    final meta = [
      if (r?.model != null) modelName(r!.model!),
      if (r?.ms != null && r!.status != 'running') '${(r.ms! / 1000).toStringAsFixed(1)} s',
      if (r?.costUsd != null) formatUsd(r!.costUsd!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: SizedBox(width: 22, child: Center(child: icon))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(color: status == 'pending' ? du.inkTertiary : du.ink))),
              if (meta.isNotEmpty) Text(meta, style: TextStyle(color: du.inkTertiary, fontSize: 12, fontFeatures: tabular)),
            ]),
            Text(
              r?.error ?? r?.summary ?? detail,
              style: TextStyle(color: r?.status == 'failed' ? du.danger : context.muted, fontSize: 13),
            ),
          ]),
        ),
      ]),
    );
  }
}

enum _Tone { warning, danger }

class _Notice extends StatelessWidget {
  const _Notice({required this.tone, required this.title, required this.body, required this.actions});

  final _Tone tone;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final (bg, line, ink) = tone == _Tone.warning ? (du.warningSubtle, du.warningLine, du.warning) : (du.dangerSubtle, du.dangerLine, du.danger);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: context.text.titleMedium?.copyWith(color: ink)),
        const SizedBox(height: 4),
        Text(body),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: actions),
      ]),
    );
  }
}

/// The accepted state, shown for a moment while the route closes.
class _Accepted extends StatelessWidget {
  const _Accepted({required this.review});

  final LabelReview review;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('${review.displayName} is in your catalogue.', style: TextStyle(color: context.muted))),
      );
}

/// The overall confidence, top right: green at or above the bar, amber below it.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.percent, {super.key, required this.bar});

  final int percent;
  final int bar;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final ok = percent >= bar;
    return Tooltip(
      message: 'How sure the reading is overall. Lines under $bar% need you.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: ok ? du.accentSubtle : du.warningSubtle, borderRadius: BorderRadius.circular(999)),
        child: Text('$percent%', style: context.text.labelMedium?.copyWith(color: ok ? du.accentText : du.warning, fontFeatures: tabular)),
      ),
    );
  }
}
