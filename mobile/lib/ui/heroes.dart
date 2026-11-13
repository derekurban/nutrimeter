// The diary's summary in the facelift looks (lib/ui/looks.dart): the day's energy against its target and the three
// macros. Two layouts, each drawn in whatever edges and dress the look has: "berries" (a big figure beside the icon's
// three berries, each grown to its macro's share) and "block" (the figure on a block of colour with a sticker, over
// three jars filling with the macros). The default look keeps its ring card (EnergySummary in nutrition.dart).
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

String _thousands(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

double _ratio(double v, double t) => t > 0 ? v / t : 0;

Widget lookHero(BuildContext context, Nutrients amounts, Map<String, ResolvedTarget> targets) {
  final d = DayFigures(amounts, targets);
  return switch (context.look.hero) {
    HeroKind.berries => _Berries(d),
    HeroKind.block => _Block(d),
    HeroKind.classic => const SizedBox.shrink(),
  };
}

/// The small line over the day's figure: the serif looks say it quietly, the chunky ones shout.
Widget _kicker(BuildContext context, {Color? color}) {
  final du = context.du, s = context.look;
  return s.serif
      ? Text('eaten so far', style: TextStyle(fontFamily: s.titleFont, fontSize: 15, fontStyle: FontStyle.italic, color: color ?? du.inkSecondary))
      : Text('TODAY\'S DAMAGE',
          style: TextStyle(fontFamily: s.titleFont, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: color ?? du.inkSecondary));
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
    final face = TextStyle(fontFamily: s.titleFont, color: du.ink);
    final left = d.remaining;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kicker(context),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_thousands(d.consumed),
                      style: face.copyWith(fontSize: 58, height: 1.0, fontWeight: s.numberWeight, letterSpacing: -2, fontFeatures: tabular)),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'of ${_thousands(d.target)} kcal  ·  ', style: TextStyle(color: du.inkSecondary)),
                    TextSpan(
                      text: left >= 0 ? '${_thousands(left)} to go' : '${_thousands(-left)} over',
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
                  child: Text(macroLabels[m.key]!, style: face.copyWith(fontSize: 16, fontWeight: s.serif ? FontWeight.w400 : FontWeight.w600)),
                ),
                Expanded(child: ProgressBar(fraction: _ratio(m.grams, m.target), color: du.macro(m.key), showLabel: false)),
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
      final share = _ratio(m.grams, m.target).clamp(0.0, 1.2);
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

// ---------------------------------------------------------------------------------------------------------------------
// Block: the day's figure on a block of colour with a sticker for the share done, and three jars filling with the
// macros.

class _Block extends StatelessWidget {
  const _Block(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final hard = s.shadow == ShadowKind.hard;
    final face = TextStyle(fontFamily: s.titleFont, color: du.ink, height: 1);
    final left = d.remaining;
    const onBlock = Color(0xFFFFFCF5);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Stack(clipBehavior: Clip.none, children: [
        SizedBox(
          width: double.infinity,
          child: Panel(
            color: s.heroColor ?? du.accentStrong,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kicker(context, color: onBlock.withValues(alpha: 0.85)),
                const SizedBox(height: 6),
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: _thousands(d.consumed),
                    style: face.copyWith(fontSize: 64, fontWeight: s.numberWeight, letterSpacing: -2.5, color: onBlock, fontFeatures: tabular),
                  ),
                  TextSpan(text: ' kcal', style: face.copyWith(fontSize: 22, fontWeight: s.serif ? FontWeight.w400 : FontWeight.w800, color: onBlock)),
                ])),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: onBlock,
                    borderRadius: BorderRadius.circular(999),
                    border: hard ? Border.all(color: du.ink, width: s.borderWidth) : null,
                  ),
                  child: Text(
                    left >= 0 ? '${_thousands(left)} left of ${_thousands(d.target)}' : '${_thousands(-left)} over ${_thousands(d.target)}',
                    style: TextStyle(fontFamily: s.bodyFont, fontSize: 14, height: 1, fontWeight: FontWeight.w600, color: left >= 0 ? du.ink : du.danger),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Positioned(
          right: 14,
          top: -10,
          child: Transform.rotate(
            angle: 0.18,
            child: Container(
              width: 82,
              height: 82,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.stickerColor ?? const Color(0xFFFFD43B),
                shape: BoxShape.circle,
                border: hard ? Border.all(color: du.ink, width: s.borderWidth) : null,
                boxShadow: hard
                    ? [BoxShadow(color: du.ink, offset: const Offset(3, 3))]
                    : [BoxShadow(color: du.ink.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 5))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(d.fraction * 100).round()}%',
                    style: face.copyWith(fontSize: 24, fontWeight: s.serif ? FontWeight.w600 : FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 1),
                Text('done',
                    style: face.copyWith(fontSize: 12.5, fontWeight: s.serif ? FontWeight.w400 : FontWeight.w600, fontStyle: s.serif ? FontStyle.italic : null)),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        for (final (i, m) in d.macros.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _Jar(macro: m)),
        ],
      ]),
    ]);
  }
}

class _Jar extends StatelessWidget {
  const _Jar({required this.macro});

  final ({String key, double grams, double target, double kcal}) macro;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final hard = s.shadow == ShadowKind.hard;
    final f = _ratio(macro.grams, macro.target);
    final over = f > 1.15;
    final strong = s.serif ? FontWeight.w600 : FontWeight.w800;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(children: [
          Text(macroLabels[macro.key]!, style: TextStyle(fontFamily: s.titleFont, fontWeight: strong, fontSize: 15, color: du.ink)),
          const SizedBox(height: 8),
          Container(
            height: 84,
            decoration: BoxDecoration(
              color: du.sunk,
              borderRadius: BorderRadius.circular(hard ? 12 : 16),
              border: hard ? Border.all(color: du.ink, width: s.borderWidth) : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: f.clamp(0.0, 1.0),
                widthFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    // full is the leaf's green in every dress, since Jam's own accent is a berry colour
                    color: over
                        ? du.danger
                        : f >= 1
                            ? const Color(0xFF7BC62D)
                            : du.macro(macro.key),
                    border: hard && f > 0 && f < 1 ? Border(top: BorderSide(color: du.ink, width: s.borderWidth)) : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('${formatAmount(macro.grams)}g',
              style: TextStyle(fontFamily: s.titleFont, fontWeight: strong, fontSize: 20, color: du.ink, fontFeatures: tabular)),
          Text('of ${formatAmount(macro.target)}g', style: context.text.bodySmall),
        ]),
      ),
    );
  }
}
