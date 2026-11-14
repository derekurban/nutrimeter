import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../logic/foods.dart';
import '../services/taxonomy_asset.dart';
import 'theme.dart';

/// A horizontal progress bar. A target fills in [color] (gray by default) and turns the accent once it is met; a
/// limit ([isLimit]) stays as it is until it is passed ([over]), then turns danger. A bar 12 or taller prints its
/// percentage inside; a thinner one prints it beside itself, unless [showLabel] is off because the figures sit next
/// to the bar already.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.fraction, this.isLimit = false, this.over = false, this.height = 12, this.color, this.showLabel = true});

  final double fraction;
  final bool isLimit;
  final bool over;
  final double height;
  final Color? color;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final pct = fraction.isFinite ? (fraction * 100).round() : 0;
    final met = !isLimit && pct >= 100; // as printed, so "100%" is never gray
    final fill = over ? du.danger : met ? du.accentStrong : (color ?? du.dataNeutral);
    final width = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    final label = TextStyle(fontFamily: appFont, fontSize: 10.5, height: 1, letterSpacing: 0, fontWeight: FontWeight.w600, fontFeatures: tabular);
    // Past halfway the percentage sits on the fill, so it takes whichever of white and near-black reads on it (the
    // calories' bar is ink: dark by day, light at night); before that it sits on the track.
    final onFill = fraction >= 0.5;
    final labelColor = !onFill ? du.ink : ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF151314);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: context.track),
          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: width, child: ColoredBox(color: fill)),
          if (height >= 12 && showLabel) Center(child: Text('$pct%', style: label.copyWith(color: labelColor))),
        ]),
      ),
    );
    return Semantics(
      value: '$pct%',
      child: height >= 12 || !showLabel
          ? bar
          : Row(children: [
              Expanded(child: bar),
              SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.right, style: label.copyWith(color: over ? du.danger : du.inkSecondary))),
            ]),
    );
  }
}

/// A surface: a soft panel with no outline. Stands in for [Card] everywhere.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.clipBehavior = Clip.none, this.color});

  final Widget child;
  final Clip clipBehavior;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Widget body = Material(type: MaterialType.transparency, child: child);
    if (clipBehavior != Clip.none) body = ClipRRect(borderRadius: BorderRadius.circular(panelRadius), clipBehavior: clipBehavior, child: body);
    return DecoratedBox(decoration: panelDecoration(context, color: color), child: body);
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
    paint.strokeCap = StrokeCap.round;
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

const macroLabels = {'protein': 'Protein', 'carbs': 'Carbs', 'fat': 'Fat'};

/// A catalogue food's picture (its category's, else its subgroup's, else its group's; or a product photo saved by an
/// older version), an initial on a sunk tile otherwise. Taxonomy pictures come from the app's bundle when it has
/// them, so they show offline; others need the network and show the initial without it.
class FoodThumb extends StatelessWidget {
  const FoodThumb({super.key, required this.food, this.size = 40});

  final Food? food;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = food;
    final url = f?.imageUrl;
    final du = context.du;
    final corner = BorderRadius.circular(math.min(10, size / 4));
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: du.sunk, borderRadius: corner),
      child: Text(
        (f?.name.isNotEmpty ?? false) ? f!.name.characters.first.toUpperCase() : '?',
        style: TextStyle(fontFamily: appFont, fontSize: size * 0.42, fontWeight: FontWeight.w600, color: du.inkSecondary),
      ),
    );
    if (url == null) return letter;
    return ClipRRect(
      borderRadius: corner,
      child: Container(
        width: size,
        height: size,
        // Old product photos were shot on white; the taxonomy pictures sit on the sunk tile like the initials.
        color: f?.source == FoodSource.off ? Colors.white : du.sunk,
        child: switch (BundledArt.assetFor(url)) {
          final asset? => Image.asset(asset, fit: BoxFit.contain, errorBuilder: (_, _, _) => letter),
          null => Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => letter),
        },
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
