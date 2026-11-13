// Playground mode: a floating berry button over the whole app that opens a dock with two rows of tabs, so the 2026-11
// facelift candidates can be tried on a phone against real data: the diary's layout (lib/ui/diary_layouts.dart) and
// the colour scheme (lib/ui/looks.dart), each chosen on its own. One tap flips either, with the app live above the
// dock. On by default in the playground flavour (app.nutrimeter.playground); Targets → Playground turns it on or off
// in any build. The choices are kept in playground.json beside the data file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../data/model.dart';
import '../data/store.dart';
import 'diary_layouts.dart';
import 'looks.dart';
import 'theme.dart';

class Playground {
  Playground._();

  /// Whether the button shows, and the chosen scheme and layout apply.
  static final enabled = ValueNotifier<bool>(appFlavor == 'playground');

  /// The colour scheme picked in the dock.
  static final chosen = ValueNotifier<Look>(Look.standard);

  /// The scheme the app wears: the chosen one in playground mode, else the default.
  static final current = ValueNotifier<Look>(Look.standard);

  /// The diary layout picked in the dock.
  static final chosenLayout = ValueNotifier<DiaryLayout>(DiaryLayout.stack);

  /// The layout the diary uses: the chosen one in playground mode, else the original stack.
  static final layout = ValueNotifier<DiaryLayout>(DiaryLayout.stack);

  static File? _file;

  static Future<void> load() async {
    try {
      _file = File('${(await getApplicationSupportDirectory()).path}/playground.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        enabled.value = j['enabled'] as bool? ?? enabled.value;
        chosen.value = Look.byId(j['look'] as String?);
        chosenLayout.value = DiaryLayout.byName(j['layout'] as String?);
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

  static void chooseLayout(DiaryLayout l) {
    chosenLayout.value = l;
    _apply();
    _save();
  }

  static void setEnabled(bool on) {
    enabled.value = on;
    _apply();
    _save();
  }

  static void _apply() {
    current.value = enabled.value ? chosen.value : Look.standard;
    layout.value = enabled.value ? chosenLayout.value : DiaryLayout.stack;
  }

  static void _save() {
    final f = _file;
    if (f == null) return;
    f.writeAsString(jsonEncode({'enabled': enabled.value, 'look': chosen.value.id, 'layout': chosenLayout.value.name})).ignore();
  }
}

/// The playground's floating button and dock, over everything (dialogs and sheets included). Wraps the app's
/// navigator through MaterialApp.builder, so nothing in it may need an Overlay (no tooltips).
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
          return LayoutBuilder(builder: (context, box) {
            final pad = MediaQuery.paddingOf(context);
            final free = Size(box.maxWidth - _size - 16, box.maxHeight - _size - pad.top - pad.bottom - 16);
            final left = 8 + _at.dx * free.width;
            final top = pad.top + 8 + _at.dy * free.height;
            return Stack(children: [
              widget.child,
              // The dock: no scrim, so the app stays live above it while the tabs are flipped.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: _open ? 0 : -260,
                child: _Dock(
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
                    onPanUpdate: (d) => setState(() => _at = Offset(
                          ((left - 8 + d.delta.dx) / free.width).clamp(0.0, 1.0),
                          ((top - pad.top - 8 + d.delta.dy) / free.height).clamp(0.0, 1.0),
                        )),
                    // let go: it settles on the nearer side
                    onPanEnd: (_) => setState(() {
                      _dragging = false;
                      _at = Offset(_at.dx < 0.5 ? 0 : 1, _at.dy);
                    }),
                    child: const _Bubble(size: _size),
                  ),
                ),
            ]);
          });
        },
      );
}

/// The floating button: the current scheme's three macro colours as berries.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    return Semantics(
      button: true,
      label: 'Playground: change the layout and colours',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: du.ink,
          shape: BoxShape.circle,
          border: Border.all(color: du.surface, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: CustomPaint(painter: _MiniBerries(Playground.current.value)),
      ),
    );
  }
}

class _MiniBerries extends CustomPainter {
  _MiniBerries(this.look);

  final Look look;

  @override
  void paint(Canvas canvas, Size s) {
    final du = look.light;
    final w = s.width;
    final colors = du.protein == null ? const [Color(0xFF7E0E4B), Color(0xFFD92B6B), Color(0xFFAE86D3)] : [du.protein!, du.carbs!, du.fat!];
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

/// The dock: a row of layout tabs and a row of colour tabs, with the sample day, the way out and a button to fold it
/// back into the berry.
class _Dock extends StatelessWidget {
  const _Dock({required this.onClose, required this.toast});

  final VoidCallback onClose;
  final void Function(String) toast;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    Widget action(IconData icon, String label, VoidCallback onTap) =>
        Semantics(label: label, child: IconButton(icon: Icon(icon, size: 20), visualDensity: VisualDensity.compact, onPressed: onTap));
    return Material(
      color: du.surface,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(context.look.radius == 0 ? 0 : 20)),
        side: BorderSide(color: du.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Row(children: [
                Expanded(child: Text('Playground', style: context.text.titleMedium)),
                action(LucideIcons.utensils, 'Fill today with a sample day', () async {
                  final n = await fillSampleDay(AppScope.read(context));
                  toast(n == 0 ? 'Foods are still loading; try again in a moment' : 'Logged $n foods to today');
                }),
                action(LucideIcons.logOut, 'Leave playground', () {
                  onClose();
                  Playground.setEnabled(false);
                  toast('Left the playground. Targets → Playground brings it back.');
                }),
                action(LucideIcons.chevronDown, 'Fold the dock away', onClose),
              ]),
            ),
            ValueListenableBuilder<DiaryLayout>(
              valueListenable: Playground.chosenLayout,
              builder: (context, chosen, _) => _TabRow(
                label: 'Layout',
                tabs: [
                  for (final l in DiaryLayout.values) _Tab(text: l.label, selected: l == chosen, onTap: () => Playground.chooseLayout(l)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<Look>(
              valueListenable: Playground.chosen,
              builder: (context, chosen, _) => _TabRow(
                label: 'Colour',
                tabs: [
                  for (final l in Look.all) _Tab(text: l.name, selected: l.id == chosen.id, swatch: l, onTap: () => Playground.choose(l)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({required this.label, required this.tabs});

  final String label;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: Row(children: [
          SizedBox(width: 68, child: Padding(padding: const EdgeInsets.only(left: 16), child: Text(label, style: context.text.labelMedium))),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => tabs[i],
            ),
          ),
        ]),
      );
}

/// One tab: filled in ink when it is the one on. A colour tab carries a dot of its scheme: its ground, ringed in its
/// ink, with its accent inside.
class _Tab extends StatelessWidget {
  const _Tab({required this.text, required this.selected, required this.onTap, this.swatch});

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final Look? swatch;

  @override
  Widget build(BuildContext context) {
    final du = context.du;
    final l = swatch?.light;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.only(left: swatch == null ? 14 : 8, right: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? du.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(context.look.radius == 0 ? 0 : 999),
          border: Border.all(color: selected ? du.ink : du.lineStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (l != null) ...[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: l.bg, shape: BoxShape.circle, border: Border.all(color: selected ? du.surface : l.ink, width: 1.5)),
              child: Container(width: 9, height: 9, decoration: BoxDecoration(color: l.carbs ?? l.accentStrong, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 7),
          ],
          Text(text, style: context.text.labelLarge?.copyWith(fontSize: 14, color: selected ? du.surface : du.ink)),
        ]),
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
