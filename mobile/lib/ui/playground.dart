// Playground mode: a floating button over the whole app that opens a drawer of looks (lib/ui/looks.dart), so the
// 2026-11 facelift candidates can be tried on a phone against real data. Everything in the app follows the chosen look
// at once. On by default in the playground flavour (app.nutrimeter.playground); Targets → Playground turns it on or off
// in any build. The choice and the button's place are kept in playground.json beside the data file.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../data/model.dart';
import '../data/store.dart';
import 'looks.dart';
import 'theme.dart';

class Playground {
  Playground._();

  /// Whether the button shows, and the chosen look applies.
  static final enabled = ValueNotifier<bool>(appFlavor == 'playground');

  /// The look picked in the drawer.
  static final chosen = ValueNotifier<Look>(Look.standard);

  /// The look the app wears: the chosen one in playground mode, else the default.
  static final current = ValueNotifier<Look>(Look.standard);

  static File? _file;

  static Future<void> load() async {
    try {
      _file = File('${(await getApplicationSupportDirectory()).path}/playground.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        enabled.value = j['enabled'] as bool? ?? enabled.value;
        chosen.value = Look.byId(j['look'] as String?);
      }
    } catch (_) {
      // A missing or broken file is just the defaults.
    }
    _apply();
  }

  static void choose(Look look) {
    chosen.value = look;
    _apply();
    _save();
  }

  static void setEnabled(bool on) {
    enabled.value = on;
    _apply();
    _save();
  }

  static void _apply() => current.value = enabled.value ? chosen.value : Look.standard;

  static void _save() {
    final f = _file;
    if (f == null) return;
    f.writeAsString(jsonEncode({'enabled': enabled.value, 'look': chosen.value.id})).ignore();
  }
}

/// The playground's floating button and drawer, over everything (dialogs and sheets included). Wraps the app's
/// navigator through MaterialApp.builder.
class PlaygroundLayer extends StatefulWidget {
  const PlaygroundLayer({super.key, required this.child, required this.messenger});

  final Widget child;
  final GlobalKey<ScaffoldMessengerState> messenger;

  @override
  State<PlaygroundLayer> createState() => _PlaygroundLayerState();
}

class _PlaygroundLayerState extends State<PlaygroundLayer> {
  static const _size = 52.0;

  /// The button's place as a share of the free area, so it survives rotation; right edge, a little above the middle.
  Offset _at = const Offset(1, 0.42);
  bool _open = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Playground.enabled,
    builder: (context, on, _) {
      if (!on) return widget.child;
      return LayoutBuilder(
        builder: (context, box) {
          final pad = MediaQuery.paddingOf(context);
          final free = Size(box.maxWidth - _size - 16, box.maxHeight - _size - pad.top - pad.bottom - 16);
          final left = 8 + _at.dx * free.width;
          final top = pad.top + 8 + _at.dy * free.height;
          return Stack(
            children: [
              widget.child,
              // the scrim and the drawer
              IgnorePointer(
                ignoring: !_open,
                child: GestureDetector(
                  onTap: () => setState(() => _open = false),
                  child: AnimatedOpacity(
                    opacity: _open ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Container(color: Colors.black.withValues(alpha: 0.38)),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: _open ? 0 : -box.maxHeight,
                child: _Drawer(
                  maxHeight: box.maxHeight * 0.82,
                  onClose: () => setState(() => _open = false),
                  toast: (m) => widget.messenger.currentState
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(m))),
                ),
              ),
              if (!_open)
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  left: left,
                  top: top,
                  child: GestureDetector(
                    onTap: () => setState(() => _open = true),
                    onPanStart: (_) => setState(() => _dragging = true),
                    onPanUpdate: (d) => setState(
                      () => _at = Offset(
                        ((left - 8 + d.delta.dx) / free.width).clamp(0.0, 1.0),
                        ((top - pad.top - 8 + d.delta.dy) / free.height).clamp(0.0, 1.0),
                      ),
                    ),
                    // let go: it settles on the nearer side
                    onPanEnd: (_) => setState(() {
                      _dragging = false;
                      _at = Offset(_at.dx < 0.5 ? 0 : 1, _at.dy);
                    }),
                    child: const _Bubble(size: _size),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

/// The floating button: the current look's three macro colours as berries.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Semantics(
      button: true,
      label: 'Playground: change the look',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: du.ink,
          shape: BoxShape.circle,
          border: Border.all(color: du.surface, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: CustomPaint(painter: _MiniBerries(Playground.current.value, size)),
      ),
    );
  }
}

class _MiniBerries extends CustomPainter {
  _MiniBerries(this.look, this.size);

  final Look look;
  final double size;

  @override
  void paint(Canvas canvas, Size s) {
    final du = look.light;
    final w = s.width;
    final colors = look.light.protein == null ? const [Color(0xFF7E0E4B), Color(0xFFD92B6B), Color(0xFFAE86D3)] : [du.protein!, du.carbs!, du.fat!];
    final spots = [Offset(w * 0.5, w * 0.38), Offset(w * 0.36, w * 0.62), Offset(w * 0.64, w * 0.62)];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(spots[i], w * 0.17, Paint()..color = colors[i]);
    }
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.6, w * 0.27)
        ..quadraticBezierTo(w * 0.64, w * 0.12, w * 0.8, w * 0.13)
        ..quadraticBezierTo(w * 0.78, w * 0.27, w * 0.6, w * 0.27),
      Paint()..color = const Color(0xFF7FB52A),
    );
  }

  @override
  bool shouldRepaint(_MiniBerries old) => old.look != look;
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.maxHeight, required this.onClose, required this.toast});

  final double maxHeight;
  final VoidCallback onClose;
  final void Function(String) toast;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final s = context.look;
    return Material(
      color: du.surface,
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(s.radius == 0 ? 0 : 24))),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<Look>(
            valueListenable: Playground.chosen,
            builder: (context, chosen, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Playground', style: context.text.headlineMedium),
                            Text('Pick a look; the whole app wears it.', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      // no tooltip: this sits above the navigator, so there is no Overlay for one
                      Semantics(
                        label: 'Close',
                        child: IconButton(icon: const Icon(LucideIcons.x), onPressed: onClose),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    children: [
                      for (final look in Look.all) _LookTile(look: look, selected: look.id == chosen.id),
                      const SizedBox(height: 8),
                      Divider(color: du.line),
                      ListTile(
                        leading: const Icon(LucideIcons.utensils),
                        title: const Text('Fill today with a sample day'),
                        subtitle: const Text('Logs a dozen everyday foods (about 1,700 kcal), so the looks have something to show'),
                        onTap: () async {
                          final n = await fillSampleDay(AppScope.read(context));
                          toast(n == 0 ? 'Foods are still loading; try again in a moment' : 'Logged $n foods to today');
                          if (n > 0) onClose();
                        },
                      ),
                      ListTile(
                        leading: const Icon(LucideIcons.logOut),
                        title: const Text('Leave playground'),
                        subtitle: const Text('Back to the default look; Targets → Playground brings it back'),
                        onTap: () {
                          onClose();
                          Playground.setEnabled(false);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One look in the drawer: a small swatch painted in its own colours and face, its name and what it is.
class _LookTile extends StatelessWidget {
  const _LookTile({required this.look, required this.selected});

  final Look look;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final l = look.brightness == Brightness.dark ? look.dark : look.light;
    final st = look.style;
    final macros = [l.macro('protein'), l.macro('carbs'), l.macro('fat')];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Playground.choose(look),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? du.ink : du.line, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              // the swatch: page, panel, the face, the macros and the accent
              Container(
                width: 76,
                height: 64,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: l.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: du.line),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: l.surface,
                    borderRadius: BorderRadius.circular(math.min(st.radius, 10)),
                    border: st.borderWidth > 0 ? Border.all(color: st.inkBorders ? l.ink : l.line, width: math.min(st.borderWidth, 1.5)) : null,
                    boxShadow: st.shadow == ShadowKind.hard ? [BoxShadow(color: l.ink, offset: const Offset(2, 2))] : null,
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(
                          fontFamily: st.titleFont,
                          fontWeight: st.titleWeight,
                          fontSize: 17,
                          height: 1.2,
                          color: l.ink,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          for (final c in macros) ...[
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 2),
                          ],
                          const Spacer(),
                          Container(
                            width: 12,
                            height: 6,
                            decoration: BoxDecoration(color: l.accentStrong, borderRadius: BorderRadius.circular(3)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      look.name,
                      style: TextStyle(
                        fontFamily: st.titleFont,
                        fontWeight: st.titleWeight,
                        fontSize: 19,
                        color: du.ink,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(look.blurb, style: context.text.bodySmall),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(LucideIcons.check, color: du.ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plausible day of everyday foods from the bundled CNF, logged to today, so a fresh install has something to show.
/// Returns how many were logged; 0 while the CNF is still loading.
Future<int> fillSampleDay(AppState state) async {
  if (!state.cnfReady) return 0;
  final today = isoDate(DateTime.now());
  // CNF's own names, so each finds exactly that food.
  const plan = [
    (Meal.breakfast, 'Cereal, hot, oats (oatmeal), instant: regular, prepared', 240.0),
    (Meal.breakfast, 'Banana, raw', 118.0),
    (Meal.breakfast, 'Milk, fluid, partly skimmed, 2% M.F.', 250.0),
    (Meal.breakfast, 'Egg, chicken, whole, cooked, boiled in shell, hard-cooked', 50.0),
    (Meal.lunch, 'Bread, whole wheat, commercial', 64.0),
    (Meal.lunch, 'Chicken, broiler, breast, meat, roasted', 120.0),
    (Meal.lunch, 'Cheese, cheddar, mild', 20.0),
    (Meal.lunch, 'Apple, raw, with skin', 180.0),
    (Meal.dinner, 'Fish, salmon, atlantic, farmed, baked or broiled', 140.0),
    (Meal.dinner, 'Grains, rice, white, long-grain, regular, cooked', 160.0),
    (Meal.dinner, 'Broccoli, boiled, drained', 90.0),
    (Meal.snacks, 'Nuts, almonds, dry roasted, unblanched', 28.0),
  ];
  var n = 0;
  for (final (meal, name, grams) in plan) {
    final found = state.cnf.search(name, limit: 20).where((f) => f.name == name).firstOrNull;
    if (found == null) continue;
    state.log(date: today, meal: meal, food: found, quantity: grams, unit: 'g');
    n++;
  }
  return n;
}
