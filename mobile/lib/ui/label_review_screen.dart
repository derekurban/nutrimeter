// The review: the full label photo on top (pan, pinch, double-tap), the record below. It opens on only the lines that
// need the person; everything else is marked off and one tap away. Tapping a line moves the photo to where it is
// printed and opens its readings: looks right, pick a reading, type it, or leave a note for the verifier. Notes go
// together in one re-read. Accepting puts the product in the catalogue and opens it for logging.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/label_review.dart';
import '../data/store.dart';
import '../logic/label_reading.dart';
import '../services/backend.dart';
import '../services/catalogue.dart';
import '../services/label_pipeline.dart';
import '../services/submissions.dart';
import 'product_flow.dart' show ConfidenceChip;
import 'theme.dart';
import 'widgets.dart';

/// A label photo from the app's storage.
class PhotoFile extends StatelessWidget {
  const PhotoFile({super.key, required this.dataDir, required this.photo, this.fit = BoxFit.contain, this.cacheWidth});

  final Directory dataDir;
  final PendingPhoto photo;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) => Image.file(
        File('${dataDir.path}/${photo.file}'),
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => Center(child: Icon(LucideIcons.imageOff, color: context.du.inkTertiary)),
      );
}

/// The lines that need the person, in the order they are asked: the label's own lines as printed, the category last.
List<ReviewLine> needsYouQueue(List<ReviewLine> lines, int bar) =>
    [...lines.where((l) => l.needsYou(bar) && l.kind != 'category'), ...lines.where((l) => l.needsYou(bar) && l.kind == 'category')];

String _roleLabel(PhotoRole r) => switch (r) {
      PhotoRole.front => 'Front',
      PhotoRole.nutrition => 'Table',
      PhotoRole.ingredients => 'Ingredients',
      PhotoRole.other => 'Photo',
    };

class LabelReviewScreen extends StatefulWidget {
  const LabelReviewScreen({super.key, required this.review, required this.onRetake, required this.onReread});

  final LabelReview review;
  final Future<void> Function(String role) onRetake;

  /// Reads the whole label again from the same photos.
  final VoidCallback onReread;

  @override
  State<LabelReviewScreen> createState() => _LabelReviewScreenState();
}

class _LabelReviewScreenState extends State<LabelReviewScreen> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  Animation<Matrix4>? _tween;
  final _edit = TextEditingController();
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  late bool _triage;
  String? _selected;
  String? _editKind; // 'value' or 'note'
  int _photo = 1; // 1-based, in orderedPhotos order
  double _fraction = 0.44;
  Size _pane = Size.zero;
  PhotoBox? _highlight;
  final _sizes = <String, Size>{};

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final t = _tween;
      if (t != null) _transform.value = t.value;
    });
    final state = AppScope.read(context);
    final lines = LabelPipeline.linesOf(state, widget.review).lines;
    final bar = state.readingSettings.bar;
    final first = needsYouQueue(lines, bar).firstOrNull ?? lines.where((l) => l.noted).firstOrNull;
    _triage = first != null;
    final table = widget.review.orderedPhotos.indexWhere((p) => p.role == PhotoRole.nutrition);
    _photo = table < 0 ? 1 : table + 1;
    if (first != null) {
      _selected = first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(first));
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    _anim.dispose();
    _edit.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AppState get _state => AppScope.read(context);
  LabelReview get _r => _state.labelReviews[widget.review.id] ?? widget.review;

  // ── The photo ──

  Future<Size?> _sizeOf(PendingPhoto p) async {
    if (p.width != null && p.height != null) return Size(p.width!.toDouble(), p.height!.toDouble());
    final cached = _sizes[p.file];
    if (cached != null) return cached;
    final dir = _state.dataDir;
    if (dir == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(await File('${dir.path}/${p.file}').readAsBytes());
      final frame = await codec.getNextFrame();
      final s = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      return _sizes[p.file] = s;
    } catch (_) {
      return null;
    }
  }

  /// Where the photo sits inside the pane (fit: contain).
  Rect _imageRect(Size image) {
    final s = _pane;
    final scale = (s.width / image.width) < (s.height / image.height) ? s.width / image.width : s.height / image.height;
    final w = image.width * scale, h = image.height * scale;
    return Rect.fromLTWH((s.width - w) / 2, (s.height - h) / 2, w, h);
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _transform.value.clone(), end: target).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  Future<void> _fit() async {
    setState(() => _highlight = null);
    _animateTo(Matrix4.identity());
  }

  /// Shows [line]'s photo and moves to where it is printed.
  Future<void> _focus(ReviewLine line) async {
    final photos = _r.orderedPhotos;
    final index = line.photo != null && line.photo! >= 1 && line.photo! <= photos.length ? line.photo! : _photo;
    if (index != _photo) {
      setState(() {
        _photo = index;
        _transform.value = Matrix4.identity();
      });
    }
    final box = line.box;
    if (box == null || _pane.isEmpty) return _fit();
    final size = await _sizeOf(photos[index - 1]);
    if (size == null || !mounted) return;
    final img = _imageRect(size);
    final rect = Rect.fromLTWH(img.left + box.x * img.width, img.top + box.y * img.height, box.w * img.width, box.h * img.height);
    final s = [_pane.width / (rect.width * 1.25), _pane.height / (rect.height * 3.2), 4.5].reduce((a, b) => a < b ? a : b).clamp(1.0, 4.5);
    final tx = _pane.width / 2 - rect.center.dx * s;
    final ty = _pane.height / 2 - rect.center.dy * s;
    setState(() => _highlight = box);
    _animateTo(Matrix4.translationValues(tx, ty, 0)..multiply(Matrix4.diagonal3Values(s, s, 1)));
  }

  // ── Decisions ──

  void _decide(ReviewLine line, LineDecision? d) {
    final r = _r;
    final decisions = {...r.decisions};
    if (d == null) {
      decisions.remove(line.id);
    } else {
      decisions[line.id] = d;
    }
    _state.putReview(r.copyWith(decisions: decisions));
    _editKind = null;
    _edit.clear();
    if (d != null) _next();
  }

  /// Moves to the next line that needs the person, or, when none is left, to the whole record (or the notes).
  void _next() {
    final state = _state;
    final lines = LabelPipeline.linesOf(state, _r).lines;
    final bar = state.readingSettings.bar;
    final next = needsYouQueue(lines, bar).firstOrNull;
    if (next != null) {
      setState(() {
        _triage = true;
        _selected = next.id;
      });
      _focus(next);
      _reveal(next.id);
      return;
    }
    final notes = _r.pendingNotes.length;
    setState(() {
      _selected = null;
      if (notes == 0) _triage = false;
    });
    _fit();
    showToast(context, notes > 0 ? 'Nothing else needs you. Send the notes when you are ready.' : 'All settled · ${overallConfidence(lines)}% confident');
  }

  void _reveal(String id) => WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[id]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 260), alignment: 0.2);
      });

  void _select(ReviewLine line) {
    setState(() {
      _selected = _selected == line.id ? null : line.id;
      _editKind = null;
      _edit.clear();
    });
    if (_selected != null) {
      _focus(line);
      _reveal(line.id);
    } else {
      _fit();
    }
  }

  void _startEdit(ReviewLine line, String kind) {
    setState(() {
      _selected = line.id;
      _editKind = kind;
      _edit.text = kind == 'value' && line.value != '—' ? line.value : (kind == 'note' ? line.decision?.note ?? '' : '');
    });
  }

  Future<void> _pickCategory(ReviewLine line) async {
    final state = _state;
    final cats = LabelPipeline.categories(state);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(categories: cats),
    );
    if (picked == null || !mounted) return;
    _decide(line, LineDecision(kind: 'chose', value: picked, at: DateTime.now()));
  }

  Future<void> _accept(List<ReviewLine> lines) async {
    final state = _state;
    final bar = state.readingSettings.bar;
    final open = lines.where((l) => l.needsYou(bar)).length;
    if (open > 0 &&
        !await confirmDialog(context, 'Accept with $open line${open == 1 ? '' : 's'} under $bar%?',
            'They are published as read. You can raise or lower the bar under Targets → Label reading.',
            action: 'Accept anyway')) {
      return;
    }
    final r = _r;
    final draft = buildRecord(r, lines, runs: r.runs);
    if (draft.problems.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Not ready to accept'),
          content: Text(draft.problems.join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    final food = catalogueFood(CatalogueRecord(id: draft.recordId, role: 'product', categoryId: draft.categoryId, data: draft.data), state.taxonomy);
    state.acceptReview(
      r.copyWith(stage: ReviewStage.accepted, acceptedAt: DateTime.now(), recordId: draft.recordId, categoryId: () => draft.categoryId, record: draft.data),
      food,
    );
    unawaited(Backend.publishReviews(state));
    if (mounted) Navigator.of(context).pop(food);
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'retake':
        final role = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: Text('Retake a photo', style: ctx.text.titleLarge), subtitle: const Text('The label is read again from the start.')),
              for (final (role, label) in [('front', 'Front'), ('nutrition', 'Nutrition table'), ('ingredients', 'Ingredients')])
                ListTile(leading: const Icon(LucideIcons.camera), title: Text(label), onTap: () => Navigator.pop(ctx, role)),
            ]),
          ),
        );
        if (role != null) await widget.onRetake(role);
      case 'reread':
        if (await confirmDialog(context, 'Read the label again?',
            'Every step runs again from these photos, at the cost of a full reading. Your answers on this product are cleared.',
            action: 'Read again')) {
          widget.onReread();
        }
      case 'discard':
        if (await confirmDialog(context, 'Discard this product?', 'Its photos and readings are deleted from this phone. Nothing is published.', action: 'Discard')) {
          _state.removeReview(_r.id);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = _r;
    final bar = state.readingSettings.bar;
    final view = LabelPipeline.linesOf(state, r);
    final lines = view.lines.where((l) => !l.hidden).toList();
    final conf = overallConfidence(lines);
    final open = needsYouQueue(lines, bar);
    final noted = lines.where((l) => l.noted).toList();
    final du = context.du;
    final photos = r.orderedPhotos;
    final dir = state.dataDir;

    return Scaffold(
      backgroundColor: du.surface,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, c) {
          final paneH = (c.maxHeight - 48) * _fraction;
          return Column(children: [
            SizedBox(
              height: 48,
              child: Row(children: [
                IconButton(icon: const Icon(LucideIcons.chevronLeft), tooltip: 'Back', onPressed: () => Navigator.of(context).pop()),
                Expanded(child: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge)),
                ConfidenceChip(conf, bar: bar),
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.ellipsisVertical),
                  onSelected: _menu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'reread', child: Text('Read the label again')),
                    PopupMenuItem(value: 'retake', child: Text('Retake a photo')),
                    PopupMenuItem(value: 'discard', child: Text('Discard this product')),
                  ],
                ),
              ]),
            ),
            SizedBox(
              height: paneH,
              child: ColoredBox(
                color: const Color(0xFF1E1C1A),
                child: LayoutBuilder(builder: (context, pc) {
                  _pane = Size(pc.maxWidth, pc.maxHeight);
                  final photo = photos.isEmpty ? null : photos[(_photo - 1).clamp(0, photos.length - 1)];
                  return Stack(children: [
                    if (photo != null && dir != null)
                      GestureDetector(
                        onDoubleTapDown: (d) {
                          final zoomed = _transform.value.getMaxScaleOnAxis() > 1.2;
                          if (zoomed) {
                            _fit();
                          } else {
                            final p = d.localPosition;
                            _animateTo(Matrix4.translationValues(-p.dx * 1.6, -p.dy * 1.6, 0)..multiply(Matrix4.diagonal3Values(2.6, 2.6, 1)));
                          }
                        },
                        onDoubleTap: () {},
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 0.8,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(400),
                          onInteractionStart: (_) => _anim.stop(),
                          child: SizedBox(
                            width: pc.maxWidth,
                            height: pc.maxHeight,
                            child: Stack(fit: StackFit.expand, children: [
                              PhotoFile(dataDir: dir, photo: photo),
                              if (_highlight != null) _Highlight(box: _highlight!, photo: photo, sizeOf: _sizeOf, pane: _pane, rectOf: _imageRect),
                            ]),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (var i = 0; i < photos.length; i++)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _photo = i + 1;
                                  _highlight = null;
                                });
                                _transform.value = Matrix4.identity();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(color: _photo == i + 1 ? Colors.white.withValues(alpha: 0.92) : null, borderRadius: BorderRadius.circular(8)),
                                child: Text(_roleLabel(photos[i].role),
                                    style: TextStyle(fontSize: 12, color: _photo == i + 1 ? const Color(0xFF1B1B1B) : const Color(0xFFDDDDDD))),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() => _fraction = (_fraction + d.delta.dy / (c.maxHeight - 48)).clamp(0.22, 0.74)),
              onVerticalDragEnd: (_) {
                final line = lines.where((l) => l.id == _selected).firstOrNull;
                line == null ? _fit() : _focus(line);
              },
              child: Container(
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: du.surface, border: Border(bottom: BorderSide(color: du.line, width: 0.6))),
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: du.lineStrong, borderRadius: BorderRadius.circular(2))),
              ),
            ),
            Expanded(child: _list(context, r, lines, open, noted, conf, bar)),
          ]);
        }),
      ),
      bottomNavigationBar: _bottom(context, r, lines, open, noted),
    );
  }

  Widget _list(BuildContext context, LabelReview r, List<ReviewLine> lines, List<ReviewLine> open, List<ReviewLine> noted, int conf, int bar) {
    final du = context.du;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 8))),
          segments: [
            ButtonSegment(value: true, label: Text(open.isEmpty && noted.isEmpty ? 'Needs you' : 'Needs you · ${open.length + noted.length}')),
            ButtonSegment(value: false, label: Text('Everything · ${lines.length}')),
          ],
          selected: {_triage},
          onSelectionChanged: (v) => setState(() {
            _triage = v.first;
            _selected = null;
            _fit();
          }),
        ),
      ),
    ];
    if (_triage) {
      // The label's own lines first; the category is a judgment, so it comes last.
      final show = [...open, ...noted.where((n) => !open.contains(n))];
      if (show.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: du.accentStrong, shape: BoxShape.circle),
              child: Icon(LucideIcons.check, color: du.onAccent),
            ),
            const SizedBox(height: 12),
            Text('All settled', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text('$conf% confident. Everything is marked off; the whole record is one tap away.', textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
          ]),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(open.isEmpty ? 'Notes ready to send' : '${open.length} line${open.length == 1 ? '' : 's'} need${open.length == 1 ? 's' : ''} your eyes',
                style: context.text.titleMedium),
            Text(
              open.isEmpty
                  ? 'Nothing else needs you. Send them and the AI looks again at just those lines.'
                  : 'The reads disagreed or the checks could not settle it. Pick what the label says, type it, or leave a note.',
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ]),
        ));
        for (final l in show) {
          children.add(_tile(context, l, bar, why: true));
        }
      }
    } else {
      if (open.isEmpty && noted.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Looks right to the reader', style: context.text.titleMedium),
            Text('$conf% confident. Everything below is marked off. Tap any line to see its readings or correct it.',
                style: TextStyle(color: context.muted, fontSize: 13)),
          ]),
        ));
      }
      String? section;
      for (final l in lines) {
        if (l.section != section) {
          section = l.section;
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(section.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.6)),
          ));
        }
        children.add(_tile(context, l, bar));
      }
      final checks = LabelPipeline.linesOf(_state, r).checks;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('CHECKS', style: context.text.labelSmall?.copyWith(letterSpacing: 0.6)),
      ));
      for (final c in checks) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(c.level == 'ok' ? LucideIcons.check : LucideIcons.triangleAlert, size: 15, color: c.level == 'ok' ? du.accentText : du.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(c.message, style: TextStyle(color: context.muted, fontSize: 13))),
          ]),
        ));
      }
    }
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Text(
        '${[for (final x in r.runs.where((x) => x.model != null && x.status == 'done')) '${x.kind.replaceAll('-', ' ')}: ${x.model}'].join(' · ')}. '
        '${formatUsdShort(r.costUsd)} so far. Every reading and check is kept with the record.',
        style: TextStyle(color: du.inkTertiary, fontSize: 12),
      ),
    ));
    return ListView(controller: _scroll, padding: EdgeInsets.zero, children: children);
  }

  Widget _tile(BuildContext context, ReviewLine l, int bar, {bool why = false}) {
    final du = context.du;
    final selected = _selected == l.id;
    final doubt = l.needsYou(bar);
    final (dotBg, dotFg, dotIcon) = l.noted
        ? (du.ink, du.bg, LucideIcons.pencil)
        : l.settledByYou
            ? (du.accentStrong, du.onAccent, LucideIcons.check)
            : doubt
                ? (du.warning, du.warningSubtle, LucideIcons.circleAlert)
                : (du.accentSubtle, du.accentText, LucideIcons.check);
    final ingredients = l.kind == 'ingredients';
    final subtitle = selected
        ? null
        : why && doubt
        ? '${l.confidence}% · ${l.reasons.firstOrNull ?? 'Below your bar.'}'
        : l.noted
            ? (l.decision?.note == askAgainNote ? 'Asked the AI to look again' : 'Note for the AI: “${l.decision?.note}”')
            : l.rereadNote != null && l.recheckNote != null
                ? 'Re-read after your note: ${l.rereadNote}'
                : null;
    return Container(
      key: _keys.putIfAbsent(l.id, GlobalKey.new),
      decoration: BoxDecoration(color: selected ? du.bg : null, border: Border(bottom: BorderSide(color: du.line, width: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _select(l),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle),
                  child: Icon(dotIcon, size: 11, color: dotFg),
                ),
              ),
              SizedBox(width: l.sub ? 22 : 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (ingredients)
                    Text(l.value, maxLines: selected ? null : 3, overflow: selected ? null : TextOverflow.ellipsis)
                  else
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(l.label, style: TextStyle(color: l.sub ? context.muted : du.ink))),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          l.value,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: doubt ? du.warning : du.ink, fontWeight: doubt ? FontWeight.w600 : FontWeight.w400, fontFeatures: tabular),
                        ),
                      ),
                    ]),
                  if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(color: du.inkTertiary, fontSize: 12.5))),
                ]),
              ),
            ]),
          ),
        ),
        if (selected) _detail(context, l, bar),
      ]),
    );
  }

  Widget _detail(BuildContext context, ReviewLine l, int bar) {
    final du = context.du;
    final readings = <String>[
      if (l.first != null && l.kind != 'ingredients') 'First read: ${l.first}',
      if (l.second != null) 'Second read: ${l.second}',
      if (l.verified != null && l.kind != 'ingredients') 'Verifier: ${l.verified}',
    ];
    final differ = l.first != null && l.second != null && l.first != l.second;
    final candidates = <String>{
      if (differ) l.first!,
      if (differ) l.second!,
      if (l.verified != null && l.verified!.isNotEmpty && l.kind != 'ingredients' && l.kind != 'text') l.verified!,
      if (differ || l.verified != null || l.reasons.isNotEmpty) ...l.alternatives,
    }.toList();
    if (candidates.length == 1 && l.first != null && !candidates.contains(l.first)) candidates.insert(0, l.first!);
    final now = DateTime.now();
    Widget chip(String label, {String? sub, bool on = false, required VoidCallback onTap, bool quiet = false}) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Material(
            color: on ? du.accentStrong : quiet ? Colors.transparent : du.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: quiet ? BorderSide.none : BorderSide(color: on ? du.accentStrong : du.lineStrong)),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontWeight: quiet ? FontWeight.w400 : FontWeight.w600, color: on ? du.onAccent : quiet ? context.muted : du.ink)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: on ? du.onAccent : du.inkTertiary)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (readings.isNotEmpty) Text(readings.join(' · '), style: TextStyle(color: context.muted, fontSize: 13)),
        if (l.reasons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l.reasons.join(' '), style: TextStyle(color: context.muted, fontSize: 13))),
        if (l.recheckNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(l.recheckNote == askAgainNote ? 'You asked the AI to look again.' : 'You asked: “${l.recheckNote}”',
                style: TextStyle(color: context.muted, fontSize: 13)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Text('${l.settledByYou ? 100 : l.confidence}% confident${l.settledByYou ? ', settled by you' : ''}',
              style: TextStyle(color: du.inkTertiary, fontSize: 12, fontFeatures: tabular)),
        ),
        Wrap(children: [
          if (l.kind == 'category') ...[
            chip('Looks right', on: l.decision?.kind == 'confirmed', onTap: () => _decide(l, LineDecision(kind: 'confirmed', at: now))),
            chip('Choose another…', quiet: true, onTap: () => _pickCategory(l)),
            chip('Ask the AI again', quiet: true, onTap: () => _decide(l, LineDecision(kind: 'note', note: askAgainNote, at: now))),
            chip('Note for the AI…', quiet: true, onTap: () => _startEdit(l, 'note')),
          ] else if (candidates.length >= 2) ...[
            for (final c in candidates)
              chip(c,
                  sub: c == l.first && c == l.second
                      ? 'both reads'
                      : c == l.first
                          ? 'first read'
                          : c == l.second
                              ? 'second read'
                              : c == l.verified
                                  ? 'verifier'
                                  : 'could be',
                  on: l.decision?.kind == 'chose' && l.decision?.value == c,
                  onTap: () => _decide(l, LineDecision(kind: 'chose', value: c, at: now))),
            chip('Type it…', quiet: true, onTap: () => _startEdit(l, 'value')),
            chip('Ask the AI again', quiet: true, onTap: () => _decide(l, LineDecision(kind: 'note', note: askAgainNote, at: now))),
            chip('Note for the AI…', quiet: true, onTap: () => _startEdit(l, 'note')),
          ] else ...[
            chip('Looks right', on: l.decision?.kind == 'confirmed', onTap: () => _decide(l, LineDecision(kind: 'confirmed', value: l.value, at: now))),
            chip('Correct it…', quiet: true, onTap: () => _startEdit(l, 'value')),
            chip('Ask the AI again', quiet: true, onTap: () => _decide(l, LineDecision(kind: 'note', note: askAgainNote, at: now))),
            chip('Note for the AI…', quiet: true, onTap: () => _startEdit(l, 'note')),
          ],
          if (l.decision != null) chip('Undo', quiet: true, onTap: () => _decide(l, null)),
        ]),
        if (_editKind != null && _selected == l.id)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _edit,
                autofocus: true,
                minLines: _editKind == 'note' || l.kind == 'ingredients' ? 2 : 1,
                maxLines: _editKind == 'note' || l.kind == 'ingredients' ? 6 : 1,
                keyboardType: _editKind == 'value' && l.kind == 'nutrient' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _editKind == 'note' ? 'What should the AI look at?' : 'As printed on the label',
                  hintText: _editKind == 'note'
                      ? 'e.g. the line under the glare reads 3 g; check it against the French column'
                      : l.kind == 'nutrient'
                          ? 'e.g. 3 g'
                          : l.kind == 'serving'
                              ? 'e.g. 1 tbsp (15 g)'
                              : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (_editKind == 'note')
                  Expanded(child: Text('Notes go together, in one re-read, when you have finished.', style: TextStyle(color: du.inkTertiary, fontSize: 12))),
                if (_editKind != 'note') const Spacer(),
                TextButton(onPressed: () => setState(() => _editKind = null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    final t = _edit.text.trim();
                    if (t.isEmpty) return;
                    _decide(l, _editKind == 'note' ? LineDecision(kind: 'note', note: t, at: now) : LineDecision(kind: 'typed', value: t, at: now));
                  },
                  child: Text(_editKind == 'note' ? 'Keep note' : 'Save'),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }

  Widget _bottom(BuildContext context, LabelReview r, List<ReviewLine> lines, List<ReviewLine> open, List<ReviewLine> noted) {
    final du = context.du;
    final List<Widget> children;
    if (_triage && open.isNotEmpty) {
      children = [
        TextButton(onPressed: () => setState(() => _triage = false), child: const Text('See everything')),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: () {
              final next = open.firstWhere((l) => l.id != _selected, orElse: () => open.first);
              setState(() => _selected = next.id);
              _focus(next);
              _reveal(next.id);
            },
            child: Text('Next · ${open.length} left'),
          ),
        ),
      ];
    } else if (noted.isNotEmpty) {
      children = [
        TextButton(onPressed: () => setState(() => _triage = !_triage), child: Text(_triage ? 'See everything' : 'Needs you')),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(LucideIcons.send, size: 18),
            onPressed: () {
              unawaited(LabelPipeline.recheck(_state, r.id));
            },
            label: Text('Send ${noted.length} line${noted.length == 1 ? '' : 's'} back to the AI'),
          ),
        ),
      ];
    } else {
      children = [
        TextButton(onPressed: () => _menu('retake'), child: const Text('Retake')),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: () => _accept(lines), child: const Text('Accept and log it'))),
      ];
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: du.surface, border: Border(top: BorderSide(color: du.line, width: 0.6))),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Row(children: children))),
    );
  }
}

String formatUsdShort(double usd) => usd < 0.995 ? '${(usd * 100).toStringAsFixed(usd < 0.1 ? 1 : 0)}¢' : '\$${usd.toStringAsFixed(2)}';

/// The line's box on the photo, with the rest dimmed. Drawn inside the zoomed content, so it moves with the photo.
class _Highlight extends StatefulWidget {
  const _Highlight({required this.box, required this.photo, required this.sizeOf, required this.pane, required this.rectOf});

  final PhotoBox box;
  final PendingPhoto photo;
  final Future<Size?> Function(PendingPhoto) sizeOf;
  final Size pane;
  final Rect Function(Size) rectOf;

  @override
  State<_Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<_Highlight> {
  Size? _size;

  @override
  void initState() {
    super.initState();
    widget.sizeOf(widget.photo).then((s) {
      if (mounted) setState(() => _size = s);
    });
  }

  @override
  void didUpdateWidget(_Highlight old) {
    super.didUpdateWidget(old);
    if (old.photo.file != widget.photo.file) {
      widget.sizeOf(widget.photo).then((s) {
        if (mounted) setState(() => _size = s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _size;
    if (s == null) return const SizedBox.shrink();
    final img = widget.rectOf(s);
    final b = widget.box;
    final rect = Rect.fromLTWH(img.left + b.x * img.width, img.top + b.y * img.height, b.w * img.width, b.h * img.height).inflate(3);
    return IgnorePointer(child: CustomPaint(painter: _HighlightPainter(rect, context.du.accentStrong)));
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => old.rect != rect || old.color != color;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.categories});

  final List<({String id, String path})> categories;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final words = _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = widget.categories.where((c) => words.every(c.path.toLowerCase().contains)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(LucideIcons.search), hintText: 'Search categories'),
            onChanged: (s) => setState(() => _q = s),
          ),
        ),
        Expanded(
          child: ListView(children: [
            ListTile(title: const Text('Uncategorized'), subtitle: const Text('None fits truthfully'), onTap: () => Navigator.pop(context, '')),
            for (final c in shown)
              ListTile(
                title: Text(c.path.split(' › ').last),
                subtitle: Text(c.path),
                onTap: () => Navigator.pop(context, c.id),
              ),
          ]),
        ),
      ]),
    );
  }
}
