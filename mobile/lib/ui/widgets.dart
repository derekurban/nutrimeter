import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../logic/foods.dart';
import 'theme.dart';

/// A horizontal progress bar with its percentage printed inside. Gray while it fills; the accent once a target is met;
/// danger once a limit is passed ([over]). A limit ([isLimit]) stays gray until then.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.fraction, this.isLimit = false, this.over = false, this.height = 16});

  final double fraction;
  final bool isLimit;
  final bool over;
  final double height;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final pct = fraction.isFinite ? (fraction * 100).round() : 0;
    final met = !isLimit && pct >= 100; // as printed, so "100%" is never gray
    final fill = over ? du.danger : met ? du.accentStrong : du.dataNeutral;
    final onFill = (over || met) && fraction >= 0.5;
    return Semantics(
      value: '$pct%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: context.track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.isFinite ? fraction.clamp(0, 1) : 0,
              child: ColoredBox(color: fill),
            ),
            Center(
              child: Text('$pct%',
                  style: context.text.labelSmall?.copyWith(
                    fontSize: 10.5,
                    height: 1,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                    color: onFill ? (over ? du.surface : du.onAccent) : du.ink,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

class RingSegment {
  const RingSegment(this.value, this.color);

  final double value;
  final Color color;
}

/// A ring whose coloured segments fill it in proportion to [total].
class Ring extends StatelessWidget {
  const Ring({super.key, required this.size, required this.stroke, required this.segments, required this.total, this.child});

  final double size;
  final double stroke;
  final List<RingSegment> segments;
  final double total;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(segments, total, stroke, context.track),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.segments, this.total, this.stroke, this.track);

  final List<RingSegment> segments;
  final double total;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    var used = 0.0;
    for (final s in segments) {
      final frac = math.max(0.0, math.min(s.value / total, 1 - used));
      if (frac <= 0) continue;
      canvas.drawArc(rect, start, frac * math.pi * 2, false, paint..color = s.color);
      start += frac * math.pi * 2;
      used += frac;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.total != total || old.segments != segments || old.track != track;
}

List<({String key, double kcal})> macroEnergy(Nutrients n) =>
    [for (final m in macroKeys) (key: m, kcal: (n[m] ?? 0) * kcalPerGram[m]!)];

const macroLabels = {'protein': 'Protein', 'carbs': 'Carbs', 'fat': 'Fat'};

/// Energy in the middle, the macro split around it, and a legend.
class MacroDonut extends StatelessWidget {
  const MacroDonut({super.key, required this.nutrients, this.size = 96});

  final Nutrients nutrients;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = macroEnergy(nutrients);
    final total = parts.fold(0.0, (a, p) => a + p.kcal);
    return Row(children: [
      Ring(
        size: size,
        stroke: size / 7,
        total: total,
        segments: [for (final p in parts) RingSegment(p.kcal, context.du.macro(p.key))],
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(formatAmount(nutrients['energy'] ?? 0, 'kcal'), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w300, fontFeatures: tabular)),
          Text('kcal', style: context.text.labelSmall),
        ]),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: context.du.macro(p.key), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(macroLabels[p.key]!)),
                Text(total > 0 ? '${(p.kcal / total * 100).round()}%' : '0%', style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: tabular)),
                SizedBox(
                  width: 64,
                  child: Text('${formatAmount(nutrients[p.key] ?? 0)} g', textAlign: TextAlign.right, style: TextStyle(color: context.muted, fontFeatures: tabular)),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Product photo for Open Food Facts items, an initial on a sunk tile otherwise.
class FoodThumb extends StatelessWidget {
  const FoodThumb({super.key, required this.food, this.size = 40});

  final Food? food;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = food;
    final url = f?.imageUrl;
    final du = context.du;
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: du.sunk, borderRadius: BorderRadius.circular(8)),
      child: Text(
        (f?.name.isNotEmpty ?? false) ? f!.name.characters.first.toUpperCase() : '?',
        style: TextStyle(fontFamily: titleFont, fontSize: size * 0.42, fontWeight: FontWeight.w500, color: du.inkSecondary),
      ),
    );
    if (url == null) return letter;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: Colors.white, // product photos are shot on white
        child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => letter),
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});

  final FoodSource source;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: du.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: du.line, width: 0.6)),
      child: Text(source.short, style: context.text.labelSmall?.copyWith(fontSize: 10.5, letterSpacing: 0, color: du.inkSecondary)),
    );
  }
}

/// Amount + unit picker for a food's servings (grams and ounces always included).
class ServingField extends StatefulWidget {
  const ServingField({super.key, required this.food, required this.quantity, required this.unit, required this.onChanged, this.autofocus = false});

  final Food? food;
  final double quantity;
  final String unit;
  final void Function(double quantity, String unit) onChanged;
  final bool autofocus;

  @override
  State<ServingField> createState() => _ServingFieldState();
}

class _ServingFieldState extends State<ServingField> {
  late final _controller = TextEditingController(text: formatQuantity(widget.quantity));

  @override
  void didUpdateWidget(ServingField old) {
    super.didUpdateWidget(old);
    final current = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (current != widget.quantity) _controller.text = formatQuantity(widget.quantity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = servingOptions(widget.food);
    final known = options.any((o) => o.label == widget.unit);
    return Row(children: [
      SizedBox(
        width: 96,
        child: TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Amount'),
          onTap: () => _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length),
          onChanged: (s) {
            final q = double.tryParse(s.replaceAll(',', '.'));
            if (q != null && q > 0) widget.onChanged(q, widget.unit);
          },
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: DropdownButtonFormField<String>(
          // Rebuild when the unit or the food's servings change (e.g. the full product arrives).
          key: ValueKey('${widget.unit}|${options.length}'),
          initialValue: widget.unit,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Unit'),
          items: [
            if (!known) DropdownMenuItem(value: widget.unit, child: Text(widget.unit, overflow: TextOverflow.ellipsis)),
            for (final o in options)
              DropdownMenuItem(
                value: o.label,
                child: Text(
                  o.label == 'g' || o.label == 'oz' ? o.label : '${o.label} · ${formatAmount(o.grams)} g',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (u) => u == null ? null : widget.onChanged(widget.quantity, u),
        ),
      ),
    ]);
  }
}

void showToast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: context.text.labelLarge?.copyWith(color: context.muted))),
          ?trailing,
        ]),
      );
}

/// Asks before something destructive; the action is in the danger colour.
Future<bool> confirmDialog(BuildContext context, String title, String body, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.du.danger, foregroundColor: ctx.du.surface),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
