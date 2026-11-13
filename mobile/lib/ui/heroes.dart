// The summary that heads the original diary layout in the facelift themes (lib/ui/looks.dart): a big figure beside
// the icon's three berries, each grown to its macro's share. The default theme keeps its ring card (EnergySummary in
// nutrition.dart). [DayFigures] and the number helpers serve every layout (lib/ui/diary_layouts.dart).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/nutrients.dart';
import '../logic/targets.dart';
import 'theme.dart';
import 'widgets.dart';

/// The numbers every summary shows.
class DayFigures {
  DayFigures(Nutrients amounts, Map<String, ResolvedTarget> targets)
      : consumed = amounts['energy'] ?? 0,
        target = targets['energy']?.target ?? 0,
        macros = [
          for (final k in macroKeys) (key: k, grams: amounts[k] ?? 0, target: targets[k]?.target ?? 0, kcal: (amounts[k] ?? 0) * kcalPerGram[k]!),
        ];

  final double consumed, target;
  final List<({String key, double grams, double target, double kcal})> macros;

  double get remaining => target - consumed;
  double get fraction => target > 0 ? consumed / target : 0;
}

String thousands(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

double ratio(double v, double t) => t > 0 ? v / t : 0;

Widget lookHero(BuildContext context, Nutrients amounts, Map<String, ResolvedTarget> targets) {
  final d = DayFigures(amounts, targets);
  return switch (context.look.hero) {
    HeroKind.berries => _Berries(d),
    HeroKind.classic => const SizedBox.shrink(),
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// Berries: a big figure, and the day's macros as the icon's three berries, each grown to its share.

class _Berries extends StatelessWidget {
  const _Berries(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final hard = s.shadow == ShadowKind.hard;
    final face = TextStyle(fontFamily: s.figures, color: du.ink);
    final left = d.remaining;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('eaten so far', style: context.text.bodyMedium?.copyWith(color: du.inkSecondary)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(thousands(d.consumed),
                      style: face.copyWith(fontSize: 58, height: 1.0, fontWeight: s.numberWeight, letterSpacing: -2, fontFeatures: tabular)),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'of ${thousands(d.target)} kcal  ·  ', style: TextStyle(color: du.inkSecondary)),
                    TextSpan(
                      text: left >= 0 ? '${thousands(left)} to go' : '${thousands(-left)} over',
                      style: TextStyle(color: left >= 0 ? du.accentText : du.danger, fontWeight: FontWeight.w600),
                    ),
                  ]),
                  style: context.text.bodyMedium,
                ),
              ]),
            ),
            SizedBox.square(dimension: 118, child: CustomPaint(painter: _BerriesPainter(d, du, hard ? s.borderWidth : 0))),
          ]),
          const SizedBox(height: 18),
          for (final m in d.macros)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: du.macro(m.key), shape: BoxShape.circle, border: hard ? Border.all(color: du.ink, width: 1.5) : null),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Text(macroLabels[m.key]!, style: face.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Expanded(child: ProgressBar(fraction: ratio(m.grams, m.target), color: du.macro(m.key), showLabel: false)),
                SizedBox(
                  width: 96,
                  child: Text('${formatAmount(m.grams)} / ${formatAmount(m.target)} g',
                      textAlign: TextAlign.right, style: context.text.bodySmall?.copyWith(fontFeatures: tabular)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BerriesPainter extends CustomPainter {
  _BerriesPainter(this.d, this.du, this.outline);

  final DayFigures d;
  final Du du;

  /// The ink outline around each berry in the outlined looks; 0 for none.
  final double outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final ink = Paint()
      ..color = du.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline;
    // Where the icon puts them: plum on top, raspberry lower left, lavender lower right; the leaf up and right.
    final spots = {'protein': Offset(w * 0.46, w * 0.38), 'carbs': Offset(w * 0.30, w * 0.66), 'fat': Offset(w * 0.66, w * 0.66)};
    final leafPath = Path()
      ..moveTo(w * 0.62, w * 0.24)
      ..quadraticBezierTo(w * 0.70, w * 0.02, w * 0.94, w * 0.04)
      ..quadraticBezierTo(w * 0.92, w * 0.26, w * 0.62, w * 0.24);
    final met = d.fraction >= 1;
    canvas.drawPath(
        leafPath,
        Paint()
          ..shader = LinearGradient(colors: [const Color(0xFFA8CC3A), met ? const Color(0xFF3E7A08) : const Color(0xFF6E9A2A)])
              .createShader(Rect.fromLTWH(w * 0.6, 0, w * 0.4, w * 0.3)));
    if (outline > 0) canvas.drawPath(leafPath, ink);
    for (final m in d.macros) {
      final c = du.macro(m.key);
      final share = ratio(m.grams, m.target).clamp(0.0, 1.2);
      final r = w * (0.11 + 0.15 * math.sqrt(share));
      final o = spots[m.key]!;
      // the whole berry as a faint ground, the eaten part as the fruit
      canvas.drawCircle(o, w * 0.26, Paint()..color = c.withValues(alpha: 0.10));
      final fruit = Paint();
      if (outline > 0) {
        fruit.color = c; // flat, like a sticker
      } else {
        fruit.shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          radius: 1.1,
          colors: [Color.lerp(c, Colors.white, 0.28)!, c, Color.lerp(c, Colors.black, 0.25)!],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: o, radius: r));
      }
      canvas.drawCircle(o, r, fruit);
      if (outline > 0) canvas.drawCircle(o, r, ink);
    }
  }

  @override
  bool shouldRepaint(_BerriesPainter old) => true;
}
