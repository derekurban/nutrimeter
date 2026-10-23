import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import 'food_detail.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the custom food editor; returns the saved food, or null if cancelled.
Future<Food?> editCustomFood(BuildContext context, {Food? food, String? barcode}) =>
    Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => CustomFoodEditor(food: food, barcode: barcode)));

/// Logs a known food straight to today's diary through its detail page.
Future<void> logFoodToday(BuildContext context, Food food) async {
  final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
    builder: (_) => FoodDetailPage(food: food, actionLabel: 'Add to diary', meal: MealLabel.forTime(DateTime.now())),
  ));
  if (result == null || !context.mounted) return;
  AppScope.read(context).log(date: isoDate(DateTime.now()), meal: result.meal!, food: result.food, quantity: result.quantity, unit: result.unit);
  showToast(context, 'Added ${result.food.name} to ${result.meal!.label}');
}

class CustomFoodsPage extends StatelessWidget {
  const CustomFoodsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final foods = state.activeCustomFoods;
    return Scaffold(
      appBar: AppBar(title: const Text('Custom foods')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'foods-new',
        icon: const Icon(Icons.add),
        label: const Text('New food'),
        onPressed: () => editCustomFood(context),
      ),
      body: foods.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Foods missing from the databases, or your own versions of products. Enter them from a nutrition label.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.muted),
                ),
              ),
            )
          : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              for (final f in foods)
                ListTile(
                  leading: FoodThumb(food: f),
                  title: Text(f.name),
                  subtitle: Text(_summary(f)),
                  onTap: () => editCustomFood(context, food: f),
                  trailing: IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'Log', onPressed: () => logFoodToday(context, f)),
                ),
            ]),
    );
  }

  static String _summary(Food f) {
    final s = f.servings.isEmpty ? const Serving('100 g', 100) : f.servings.first;
    final k = s.grams / 100;
    final n = f.nutrients;
    return '${s.label} · ${formatAmount((n['energy'] ?? 0) * k, 'kcal')} kcal · '
        'P ${formatAmount((n['protein'] ?? 0) * k)} · C ${formatAmount((n['carbs'] ?? 0) * k)} · F ${formatAmount((n['fat'] ?? 0) * k)}';
  }
}

class CustomFoodEditor extends StatefulWidget {
  const CustomFoodEditor({super.key, this.food, this.barcode});

  final Food? food;
  final String? barcode;

  @override
  State<CustomFoodEditor> createState() => _CustomFoodEditorState();
}

class _ServingRow {
  _ServingRow(String label, double grams)
      : label = TextEditingController(text: label),
        grams = TextEditingController(text: grams > 0 ? formatAmount(grams) : '');

  final TextEditingController label;
  final TextEditingController grams;

  double get gramsValue => double.tryParse(grams.text.replaceAll(',', '.')) ?? 0;
}

class _CustomFoodEditorState extends State<CustomFoodEditor> {
  late final _name = TextEditingController(text: widget.food?.name ?? '');
  late final _brand = TextEditingController(text: widget.food?.brand ?? '');
  late final List<_ServingRow> _servings = [
    for (final s in (widget.food?.servings.isNotEmpty ?? false) ? widget.food!.servings : const [Serving('serving', 0)]) _ServingRow(s.label, s.grams),
  ];
  late final Map<String, TextEditingController> _values;

  /// true = values are per the first serving (like a nutrition label); false = per 100 g.
  bool _perServing = true;
  late bool _showAll = nutrients.any((d) => !d.core && !d.derived && widget.food?.nutrients[d.key] != null);
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.food?.servings.isNotEmpty ?? false ? widget.food!.servings.first.grams : 100.0;
    if (widget.food != null && widget.food!.servings.isEmpty) _perServing = false;
    _values = {
      for (final d in nutrients.where((d) => !d.derived))
        d.key: TextEditingController(text: _fmt(widget.food?.nutrients[d.key], _perServing ? base / 100 : 1)),
    };
  }

  static String _fmt(double? per100, double factor) =>
      per100 == null ? '' : (per100 * factor).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    for (final s in _servings) {
      s.label.dispose();
      s.grams.dispose();
    }
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _basisGrams => _perServing ? (_servings.isEmpty ? 0 : _servings.first.gramsValue) : 100;

  void _switchBasis(bool perServing) {
    if (perServing == _perServing) return;
    final from = _basisGrams;
    final to = perServing ? (_servings.isEmpty ? 0.0 : _servings.first.gramsValue) : 100.0;
    if (from > 0 && to > 0) {
      for (final c in _values.values) {
        final v = double.tryParse(c.text.replaceAll(',', '.'));
        if (v != null) c.text = _fmt(v * 100 / from, to / 100);
      }
    }
    setState(() => _perServing = perServing);
  }

  void _save() {
    final name = _name.text.trim();
    final basis = _basisGrams;
    final energy = double.tryParse(_values['energy']!.text.replaceAll(',', '.'));
    final error = name.isEmpty
        ? 'Give the food a name.'
        : basis <= 0
            ? 'The first serving needs a weight in grams.'
            : energy == null
                ? 'Energy (kcal) is required.'
                : null;
    if (error != null) return setState(() => _error = error);
    final per100 = <String, double>{
      for (final e in _values.entries)
        if (double.tryParse(e.value.text.replaceAll(',', '.')) case final v?) e.key: v * 100 / basis,
    };
    final food = Food(
      id: widget.food?.id ?? 'custom:${newId()}',
      source: FoodSource.custom,
      name: name,
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: widget.food?.barcode ?? widget.barcode,
      nutrients: per100,
      servings: [
        for (final s in _servings)
          if (s.label.text.trim().isNotEmpty && s.gramsValue > 0) Serving(s.label.text.trim(), s.gramsValue),
      ],
    );
    AppScope.read(context).saveCustomFood(food);
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final editable = nutrients.where((d) => !d.derived && (_showAll || d.core));
    final first = _servings.isEmpty ? null : _servings.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.food == null ? 'New custom food' : 'Edit custom food'),
        actions: [
          if (widget.food != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await confirmDialog(context, 'Delete “${widget.food!.name}”?', 'Diary entries that use it are kept.');
                if (!ok || !context.mounted) return;
                AppScope.read(context).archiveCustomFood(widget.food!.id);
                Navigator.of(context).pop();
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
        TextField(controller: _name, autofocus: widget.food == null, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
        if ((widget.food?.barcode ?? widget.barcode) != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Barcode ${widget.food?.barcode ?? widget.barcode}', style: TextStyle(color: context.muted)),
          ),
        const SectionTitle('Serving sizes'),
        Text('Grams and ounces are always available. The first serving is the default when logging.', style: TextStyle(color: context.muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final (i, s) in _servings.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(flex: 3, child: TextField(controller: s.label, decoration: const InputDecoration(hintText: 'e.g. bar, slice, cup'))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: s.grams,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(suffixText: 'g'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove serving',
                onPressed: _servings.length == 1 ? null : () => setState(() => _servings.removeAt(i)),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add serving size'),
            onPressed: () => setState(() => _servings.add(_ServingRow('', 0))),
          ),
        ),
        const SectionTitle('Nutrition facts'),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text('Per ${first?.label.text.trim().isNotEmpty ?? false ? first!.label.text.trim() : 'serving'}')),
            const ButtonSegment(value: false, label: Text('Per 100 g')),
          ],
          selected: {_perServing},
          onSelectionChanged: (s) => _switchBasis(s.first),
        ),
        const SizedBox(height: 8),
        for (final group in NutrientGroup.values)
          if (editable.where((d) => d.group == group).toList() case final defs when defs.isNotEmpty) ...[
            if (_showAll) Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(group.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            for (final d in defs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: d.sub ? 14 : 0),
                      child: Text(d.label, style: TextStyle(color: d.sub ? context.muted : null)),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _values[d.key],
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: InputDecoration(suffixText: d.unit, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    ),
                  ),
                ]),
              ),
          ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Show fewer nutrients' : 'Show all nutrients (vitamins, minerals, lipids…)'),
          ),
        ),
      ]),
    );
  }
}
