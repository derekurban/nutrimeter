// The diary's summary in each facelift look (lib/ui/looks.dart): the day's energy against its target and the three
// macros, drawn the look's own way. The default look keeps its ring card (EnergySummary in nutrition.dart).
import 'dart:math' as math;
import 'dart:ui' as ui;

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
      ],
      extras = [
        for (final k in ['fiber', 'sugars', 'satFat', 'sodium'])
          if (nutrientByKey[k] != null) (def: nutrientByKey[k]!, value: amounts[k], target: targets[k]),
      ];

  final double consumed, target;
  final List<({String key, double grams, double target, double kcal})> macros;
  final List<({NutrientDef def, double? value, ResolvedTarget? target})> extras;

  double get remaining => target - consumed;
  double get fraction => target > 0 ? consumed / target : 0;
  double get macroKcal => macros.fold(0.0, (a, m) => a + m.kcal);
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
    HeroKind.orchard => _Orchard(d),
    HeroKind.facts => _Facts(d),
    HeroKind.jam => _Jam(d),
    HeroKind.gauge => _Gauge(d),
    HeroKind.receipt => _Receipt(d),
    HeroKind.riso => _Riso(d),
    HeroKind.classic => const SizedBox.shrink(),
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// Orchard: a big soft serif figure, and the day's macros as the icon's three berries, each grown to its share.

class _Orchard extends StatelessWidget {
  const _Orchard(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final serif = TextStyle(fontFamily: s.titleFont, color: du.ink);
    final left = d.remaining;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'eaten so far',
                        style: serif.copyWith(fontSize: 15, fontStyle: FontStyle.italic, color: du.inkSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _thousands(d.consumed),
                        style: serif.copyWith(fontSize: 58, height: 1.0, fontWeight: FontWeight.w300, letterSpacing: -2, fontFeatures: tabular),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'of ${_thousands(d.target)} kcal  ·  ',
                              style: TextStyle(color: du.inkSecondary),
                            ),
                            TextSpan(
                              text: left >= 0 ? '${_thousands(left)} to go' : '${_thousands(-left)} over',
                              style: TextStyle(color: left >= 0 ? du.accentText : du.danger, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                SizedBox.square(dimension: 118, child: CustomPaint(painter: _BerriesPainter(d, du))),
              ],
            ),
            const SizedBox(height: 18),
            for (final m in d.macros)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: du.macro(m.key), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 62, child: Text(macroLabels[m.key]!, style: serif.copyWith(fontSize: 16))),
                    Expanded(
                      child: ProgressBar(fraction: _ratio(m.grams, m.target), color: du.macro(m.key), showLabel: false),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        '${formatAmount(m.grams)} / ${formatAmount(m.target)} g',
                        textAlign: TextAlign.right,
                        style: context.text.bodySmall?.copyWith(fontFeatures: tabular),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BerriesPainter extends CustomPainter {
  _BerriesPainter(this.d, this.du);

  final DayFigures d;
  final Du du;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
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
        ..shader = LinearGradient(
          colors: [const Color(0xFFA8CC3A), met ? const Color(0xFF3E7A08) : const Color(0xFF6E9A2A)],
        ).createShader(Rect.fromLTWH(w * 0.6, 0, w * 0.4, w * 0.3)),
    );
    for (final m in d.macros) {
      final c = du.macro(m.key);
      final share = _ratio(m.grams, m.target).clamp(0.0, 1.2);
      final r = w * (0.11 + 0.15 * math.sqrt(share));
      final o = spots[m.key]!;
      // the unfilled berry as a faint outline, the eaten part as the shaded fruit
      canvas.drawCircle(o, w * 0.26, Paint()..color = c.withValues(alpha: 0.10));
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.5),
            radius: 1.1,
            colors: [Color.lerp(c, Colors.white, 0.28)!, c, Color.lerp(c, Colors.black, 0.25)!],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: o, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_BerriesPainter old) => true;
}

// ---------------------------------------------------------------------------------------------------------------------
// Facts: the day printed as a Nutrition Facts panel, % of your targets in place of the Daily Value.

class _Facts extends StatelessWidget {
  const _Facts(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final heavy = TextStyle(fontFamily: s.titleFont, color: du.ink, height: 1.05);
    final body = TextStyle(fontFamily: s.bodyFont, color: du.ink, fontSize: 16, height: 1.2);
    Widget rule(double h) => Container(height: h, color: du.ink, margin: const EdgeInsets.symmetric(vertical: 4));
    Widget row(String label, String amount, double? pct, {bool bold = true, bool indent = false, bool over = false}) => Column(
      children: [
        Row(
          children: [
            SizedBox(width: indent ? 16 : 0),
            Text(label, style: bold ? body.copyWith(fontWeight: FontWeight.w700) : body),
            const SizedBox(width: 6),
            Text(amount, style: body.copyWith(fontFeatures: tabular)),
            const Spacer(),
            if (pct != null)
              Text(
                '${(pct * 100).round()}%',
                style: body.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular, color: over ? du.danger : du.ink),
              ),
          ],
        ),
        Container(height: 1, color: du.ink, margin: const EdgeInsets.only(top: 4, bottom: 4)),
      ],
    );
    final m = {for (final x in d.macros) x.key: x};
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nutrition Facts', style: heavy.copyWith(fontSize: 38, letterSpacing: -1.2)),
            Container(height: 1, color: du.ink, margin: const EdgeInsets.symmetric(vertical: 4)),
            Row(
              children: [
                Text('Eaten today', style: body.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('target ${_thousands(d.target)} kcal', style: body),
              ],
            ),
            rule(10),
            Text('Amount so far', style: body.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Calories', style: heavy.copyWith(fontSize: 30, letterSpacing: -0.8)),
                const Spacer(),
                Text(_thousands(d.consumed), style: heavy.copyWith(fontSize: 46, letterSpacing: -1.5, fontFeatures: tabular)),
              ],
            ),
            rule(5),
            Align(
              alignment: Alignment.centerRight,
              child: Text('% Target*', style: body.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            Container(height: 1, color: du.ink, margin: const EdgeInsets.only(top: 4, bottom: 4)),
            row('Total Fat', '${formatAmount(m['fat']!.grams)}g', _ratio(m['fat']!.grams, m['fat']!.target)),
            for (final e in d.extras.where((e) => e.def.key == 'satFat'))
              row(
                'Saturated Fat',
                '${formatAmount(e.value)}g',
                e.target?.max != null ? _ratio(e.value ?? 0, e.target!.max!) : null,
                bold: false,
                indent: true,
                over: e.target?.max != null && (e.value ?? 0) > e.target!.max!,
              ),
            for (final e in d.extras.where((e) => e.def.key == 'sodium'))
              row(
                'Sodium',
                '${formatAmount(e.value)}mg',
                e.target?.max != null ? _ratio(e.value ?? 0, e.target!.max!) : null,
                over: e.target?.max != null && (e.value ?? 0) > e.target!.max!,
              ),
            row('Total Carbohydrate', '${formatAmount(m['carbs']!.grams)}g', _ratio(m['carbs']!.grams, m['carbs']!.target)),
            for (final e in d.extras.where((e) => e.def.key == 'fiber'))
              row(
                'Dietary Fibre',
                '${formatAmount(e.value)}g',
                e.target?.target != null ? _ratio(e.value ?? 0, e.target!.target!) : null,
                bold: false,
                indent: true,
              ),
            for (final e in d.extras.where((e) => e.def.key == 'sugars'))
              row('Total Sugars', '${formatAmount(e.value)}g', null, bold: false, indent: true),
            Column(
              children: [
                Row(
                  children: [
                    Text('Protein', style: body.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text('${formatAmount(m['protein']!.grams)}g', style: body.copyWith(fontFeatures: tabular)),
                    const Spacer(),
                    Text(
                      '${(_ratio(m['protein']!.grams, m['protein']!.target) * 100).round()}%',
                      style: body.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                    ),
                  ],
                ),
              ],
            ),
            rule(10),
            Text(
              '* The percent of your own daily targets. ${d.remaining >= 0 ? '${_thousands(d.remaining)} calories left today.' : '${_thousands(-d.remaining)} calories over today.'}',
              style: body.copyWith(fontSize: 12.5, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Jam: a raspberry sticker with the day's number on it, and three jars filling with the macros.

class _Jam extends StatelessWidget {
  const _Jam(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final chunky = TextStyle(fontFamily: s.titleFont, fontWeight: FontWeight.w800, color: du.ink, height: 1);
    final left = d.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: Panel(
                color: du.accentStrong,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TODAY\'S DAMAGE', style: chunky.copyWith(fontSize: 13, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _thousands(d.consumed),
                              style: chunky.copyWith(fontSize: 64, letterSpacing: -2.5, color: Colors.white),
                            ),
                            TextSpan(
                              text: ' kcal',
                              style: chunky.copyWith(fontSize: 22, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: du.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: du.ink, width: 2),
                        ),
                        child: Text(
                          left >= 0 ? '${_thousands(left)} left of ${_thousands(d.target)}' : '${_thousands(-left)} over ${_thousands(d.target)}!',
                          style: chunky.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
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
                    color: const Color(0xFFFFD43B),
                    shape: BoxShape.circle,
                    border: Border.all(color: du.ink, width: 2),
                    boxShadow: [BoxShadow(color: du.ink, offset: const Offset(3, 3))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(d.fraction * 100).round()}%', style: chunky.copyWith(fontSize: 24, letterSpacing: -1)),
                      Text('done', style: chunky.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final (i, m) in d.macros.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: _Jar(macro: m))],
          ],
        ),
      ],
    );
  }
}

class _Jar extends StatelessWidget {
  const _Jar({required this.macro});

  final ({String key, double grams, double target, double kcal}) macro;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final f = _ratio(macro.grams, macro.target);
    final over = f > 1.15;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          children: [
            Text(
              macroLabels[macro.key]!,
              style: TextStyle(fontFamily: s.titleFont, fontWeight: FontWeight.w800, fontSize: 15, color: du.ink),
            ),
            const SizedBox(height: 8),
            Container(
              height: 84,
              decoration: BoxDecoration(
                color: du.sunk,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: du.ink, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: f.clamp(0.0, 1.0),
                  widthFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: over
                          ? du.danger
                          : f >= 1
                          ? const Color(0xFF7BC62D)
                          : du.macro(macro.key),
                      border: Border(
                        top: BorderSide(color: du.ink, width: f > 0 && f < 1 ? 2 : 0),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatAmount(macro.grams)}g',
              style: TextStyle(fontFamily: s.titleFont, fontWeight: FontWeight.w800, fontSize: 20, color: du.ink, fontFeatures: tabular),
            ),
            Text('of ${formatAmount(macro.target)}g', style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Nightshade: a 270° gauge with tick marks, glowing as it fills, the three macros as thin arcs inside it.

class _Gauge extends StatelessWidget {
  const _Gauge(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final left = d.remaining;
    return Panel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          children: [
            SizedBox(
              height: 280,
            width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _GaugePainter(d, du))),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ENERGY',
                        style: TextStyle(
                          fontFamily: s.bodyFont,
                          fontSize: 11,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.w700,
                          color: du.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _thousands(d.consumed),
                        style: TextStyle(
                          fontFamily: s.titleFont,
                          fontSize: 38,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1.5,
                          color: du.ink,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(
                        '/ ${_thousands(d.target)} kcal',
                        style: TextStyle(fontFamily: s.bodyFont, fontSize: 13, color: du.inkSecondary),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: left >= 0 ? du.accentSubtle : du.dangerSubtle,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: left >= 0 ? du.accentLine : du.dangerLine),
                      ),
                      child: Text(
                        left >= 0 ? '${_thousands(left)} LEFT' : '${_thousands(-left)} OVER',
                        style: TextStyle(
                          fontFamily: s.titleFont,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w500,
                          color: left >= 0 ? du.accentText : du.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final m in d.macros)
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: du.macro(m.key),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: du.macro(m.key), blurRadius: 6)],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              macroLabels[m.key]!.toUpperCase(),
                              style: TextStyle(
                                fontFamily: s.bodyFont,
                                fontSize: 10.5,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                                color: du.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatAmount(m.grams),
                                style: TextStyle(fontFamily: s.titleFont, fontSize: 20, fontWeight: FontWeight.w500, color: du.ink),
                              ),
                              TextSpan(
                                text: ' / ${formatAmount(m.target)}g',
                                style: TextStyle(fontFamily: s.bodyFont, fontSize: 12, color: du.inkTertiary),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.d, this.du);

  final DayFigures d;
  final Du du;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 6);
    final r = math.min(size.width, size.height) / 2 - 8;
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    // ticks
    for (var i = 0; i <= 40; i++) {
      final a = start + sweep * i / 40;
      final major = i % 10 == 0;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r + 2);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - (major ? 10 : 5));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = du.lineStrong
          ..strokeWidth = major ? 2 : 1,
      );
    }
    final arc = Rect.fromCircle(center: c, radius: r - 46);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = du.sunk;
    canvas.drawArc(arc, start, sweep, false, track);
    final f = d.fraction.clamp(0.0, 1.0);
    if (f > 0) {
      final gradient = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        tileMode: TileMode.clamp,
        colors: d.fraction > 1 ? [du.danger, du.danger] : [du.macro('protein'), du.macro('carbs'), du.accentStrong],
        transform: const GradientRotation(0),
      ).createShader(arc);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(arc, start, sweep * f, false, glow);
      canvas.drawArc(
        arc,
        start,
        sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..shader = gradient,
      );
    }
    // the macros, inside
    for (final (i, m) in d.macros.indexed) {
      final rr = r - 16 - i * 8.0;
      final rect = Rect.fromCircle(center: c, radius: rr);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = du.sunk,
      );
      final mf = _ratio(m.grams, m.target).clamp(0.0, 1.0);
      if (mf > 0) {
        canvas.drawArc(
          rect,
          start,
          sweep * mf,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = du.macro(m.key),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => true;
}

// ---------------------------------------------------------------------------------------------------------------------
// Receipt: the day as a till receipt, a balance due at the bottom and a torn edge.

class _Receipt extends StatelessWidget {
  const _Receipt(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final mono = TextStyle(fontFamily: s.bodyFont, color: du.ink, fontSize: 13, height: 1.5, fontFeatures: tabular);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    Widget line(String a, String b, {TextStyle? style}) => Row(
      children: [
        Text(a, style: style ?? mono),
        Expanded(
          child: Text(
            ' ${'.' * 60}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: (style ?? mono).copyWith(color: du.line),
          ),
        ),
        Text(b, style: style ?? mono),
      ],
    );
    final big = mono.copyWith(fontFamily: s.titleFont, fontSize: 18, fontWeight: FontWeight.w700);
    return ClipPath(
      clipper: _TornEdge(),
      child: Container(
        color: du.surface,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('NUTRIMETER', textAlign: TextAlign.center, style: big.copyWith(fontSize: 20, letterSpacing: 4)),
            Text(
              'DAILY INTAKE · TICKET',
              textAlign: TextAlign.center,
              style: mono.copyWith(fontSize: 11, letterSpacing: 2, color: du.inkSecondary),
            ),
            Text(
              '${two(now.day)}/${two(now.month)}/${now.year}  ${two(now.hour)}:${two(now.minute)}',
              textAlign: TextAlign.center,
              style: mono.copyWith(fontSize: 11, color: du.inkSecondary),
            ),
            const DashedRule(height: 20),
            for (final m in d.macros) ...[
              line(macroLabels[m.key]!.toUpperCase(), '${formatAmount(m.grams)} g'),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  '@ target ${formatAmount(m.target)} g  ${(_ratio(m.grams, m.target) * 100).round()}%',
                  style: mono.copyWith(fontSize: 11.5, color: du.inkSecondary),
                ),
              ),
            ],
            const DashedRule(height: 20),
            line('SUBTOTAL KCAL', _thousands(d.consumed)),
            line('BUDGET KCAL', _thousands(d.target)),
            const SizedBox(height: 4),
            Text(
              '=' * 60,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: mono.copyWith(color: du.lineStrong, height: 1),
            ),
            const SizedBox(height: 4),
            line(
              d.remaining >= 0 ? 'BALANCE' : 'OVER BY',
              '${_thousands(d.remaining.abs())} KCAL',
              style: big.copyWith(color: d.remaining >= 0 ? du.ink : du.danger),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 34,
              child: CustomPaint(
                painter: _BarcodePainter(seed: d.consumed.round() * 31 + d.target.round(), color: du.ink),
              ),
            ),
            const SizedBox(height: 6),
            Text('*** THANK YOU · EAT WELL ***', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 11, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _TornEdge extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const tooth = 9.0, depth = 7.0;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - depth);
    var x = size.width;
    var up = false;
    while (x > 0) {
      x -= tooth / 2;
      p.lineTo(math.max(x, 0), up ? size.height - depth : size.height);
      up = !up;
    }
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_TornEdge old) => false;
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..color = color;
    final width = size.width * 0.7;
    var x = (size.width - width) / 2;
    final end = x + width;
    while (x < end) {
      final w = 1.0 + rnd.nextInt(3);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w + 1 + rnd.nextInt(3);
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------------------------------------------------
// Riso: two inks on paper. The macros as overprinting circles (pink over blue makes the purple), the figure printed
// slightly off-register, and grain over all of it.

const _risoPink = Color(0xFFFF48B0);
const _risoBlue = Color(0xFF0078BF);

class _Riso extends StatelessWidget {
  const _Riso(this.d);

  final DayFigures d;

  @override
  Widget build(BuildContext context) {
    final du = context.du, s = context.look;
    final display = TextStyle(fontFamily: s.titleFont, fontWeight: FontWeight.w800, height: 0.95, letterSpacing: -2, fontFeatures: tabular);
    Widget misregistered(String text, double size) => Stack(
      children: [
        Transform.translate(
          offset: const Offset(2.5, 2),
          child: Text(
            text,
            style: display.copyWith(fontSize: size, color: _risoPink.withValues(alpha: 0.9)),
          ),
        ),
        Text(
          text,
          style: display.copyWith(fontSize: size, color: _risoBlue.withValues(alpha: 0.88)),
        ),
      ],
    );
    final left = d.remaining;
    return Panel(
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        foregroundPainter: GrainPainter(color: du.ink),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KCAL TODAY',
                          style: TextStyle(fontFamily: s.bodyFont, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600, color: _risoBlue),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: misregistered(_thousands(d.consumed), 62)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          color: (left >= 0 ? _risoBlue : _risoPink).withValues(alpha: 0.9),
                          child: Text(
                            left >= 0 ? '${_thousands(left)} TO GO / ${_thousands(d.target)}' : '${_thousands(-left)} OVER / ${_thousands(d.target)}',
                            style: TextStyle(
                              fontFamily: s.titleFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: du.surface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox.square(dimension: 108, child: CustomPaint(painter: _OverprintPainter(d))),
                ],
              ),
              const SizedBox(height: 18),
              for (final m in d.macros)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(
                          macroLabels[m.key]!.toUpperCase(),
                          style: TextStyle(
                            fontFamily: s.titleFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: du.macro(m.key),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ProgressBar(fraction: _ratio(m.grams, m.target), color: du.macro(m.key).withValues(alpha: 0.85)),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          '${formatAmount(m.grams)}/${formatAmount(m.target)}g',
                          textAlign: TextAlign.right,
                          style: context.text.bodySmall?.copyWith(fontFeatures: tabular, color: du.ink),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverprintPainter extends CustomPainter {
  _OverprintPainter(this.d);

  final DayFigures d;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.saveLayer(Offset.zero & size, Paint());
    final m = {for (final x in d.macros) x.key: x};
    double r(String k) => w * (0.14 + 0.16 * math.sqrt(_ratio(m[k]!.grams, m[k]!.target).clamp(0.0, 1.2)));
    // halftone: the whole day's target as a dotted disc, what is eaten printed solid over it
    final dots = Paint()..color = _risoBlue.withValues(alpha: 0.35);
    for (var y = 3.0; y < w; y += 7) {
      for (var x = 3.0; x < w; x += 7) {
        if ((Offset(x, y) - Offset(w / 2, w / 2)).distance < w * 0.47) canvas.drawCircle(Offset(x, y), 1.4, dots);
      }
    }
    final blend = Paint()..blendMode = BlendMode.multiply;
    canvas.drawCircle(Offset(w * 0.38, w * 0.40), r('protein'), blend..color = _risoBlue.withValues(alpha: 0.88));
    canvas.drawCircle(Offset(w * 0.62, w * 0.44), r('carbs'), blend..color = _risoPink.withValues(alpha: 0.88));
    canvas.drawCircle(Offset(w * 0.50, w * 0.66), r('fat'), blend..color = _risoBlue.withValues(alpha: 0.6));
    canvas.drawCircle(Offset(w * 0.52, w * 0.67), r('fat'), blend..color = _risoPink.withValues(alpha: 0.6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverprintPainter old) => true;
}

/// Paper grain: fine specks, the same every time.
class GrainPainter extends CustomPainter {
  GrainPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final n = (size.width * size.height / 90).round();
    final light = Paint()..color = color.withValues(alpha: 0.07);
    final dark = Paint()..color = color.withValues(alpha: 0.12);
    final pts = <Offset>[], pts2 = <Offset>[];
    for (var i = 0; i < n; i++) {
      (i % 3 == 0 ? pts2 : pts).add(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height));
    }
    canvas.drawPoints(ui.PointMode.points, pts, light..strokeWidth = 1.2);
    canvas.drawPoints(ui.PointMode.points, pts2, dark..strokeWidth = 0.9);
  }

  @override
  bool shouldRepaint(GrainPainter old) => old.color != color;
}
