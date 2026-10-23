import 'package:flutter/material.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import 'nutrition.dart';
import 'theme.dart';
import 'widgets.dart';

class PickResult {
  const PickResult(this.food, this.quantity, this.unit, this.grams, this.meal);

  final Food food;
  final double quantity;
  final String unit;
  final double grams;
  final Meal? meal;
}

/// One food: choose an amount, see its nutrition against your targets, then confirm.
/// Open Food Facts search hits are completed here with the full product (micros, servings).
class FoodDetailPage extends StatefulWidget {
  const FoodDetailPage({super.key, required this.food, required this.actionLabel, this.meal, this.initialQuantity, this.initialUnit});

  final Food food;
  final String actionLabel;

  /// When set, a meal selector is shown and the result carries the chosen meal.
  final Meal? meal;
  final double? initialQuantity;
  final String? initialUnit;

  @override
  State<FoodDetailPage> createState() => _FoodDetailPageState();
}

class _FoodDetailPageState extends State<FoodDetailPage> {
  late Food _food = widget.food;
  late double _quantity;
  late String _unit;
  late Meal? _meal = widget.meal;
  bool _loading = false;
  bool _touched = false;
  bool _showAll = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantity != null && widget.initialUnit != null) {
      _quantity = widget.initialQuantity!;
      _unit = widget.initialUnit!;
      _touched = true;
    } else {
      _applyDefault(_food);
    }
    if (_food.source == FoodSource.off && !_food.complete && _food.barcode != null) _complete(_food.barcode!);
  }

  void _applyDefault(Food food) {
    final d = defaultServing(food);
    _quantity = d.quantity;
    _unit = d.unit.label;
  }

  Future<void> _complete(String barcode) async {
    setState(() => _loading = true);
    final state = AppScope.read(context);
    try {
      final full = await state.off.product(barcode);
      if (!mounted || full == null) return;
      state.cacheFood(full);
      setState(() {
        _food = full;
        if (!_touched) _applyDefault(full);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Showing search data only: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final grams = gramsFor(_food, _quantity, _unit);
    final scaled = withDerived(scaleTo(_food.nutrients, grams));
    return Scaffold(
      appBar: AppBar(title: Text(_food.source.label, style: context.text.titleMedium)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FoodThumb(food: _food, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_food.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (_food.brand != null) Text(_food.brand!, style: TextStyle(color: context.muted)),
              if (_food.barcode != null) Text(_food.barcode!, style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
          ),
        ]),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.muted))),
        if (!_food.hasNutrition && !_loading)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Palette.vitamins.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Text('Open Food Facts has no nutrition data for this product yet. Add it as a custom food instead.'),
          ),
        const SizedBox(height: 18),
        ServingField(
          food: _food,
          quantity: _quantity,
          unit: _unit,
          autofocus: widget.initialQuantity != null,
          onChanged: (q, u) => setState(() {
            _touched = true;
            _quantity = q;
            _unit = u;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('= ${formatAmount(grams)} g', style: TextStyle(color: context.muted)),
        ),
        if (_meal != null) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final m in Meal.values)
              ChoiceChip(label: Text(m.label), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
          ]),
        ],
        const SizedBox(height: 18),
        MacroDonut(nutrients: scaled),
        const SizedBox(height: 10),
        NutritionPreview(amounts: scaled, targets: state.resolvedTargets, showAll: _showAll),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Show key nutrients' : 'Show all available nutrients'),
          ),
        ),
        Text('% = share of your daily target', style: TextStyle(color: context.muted, fontSize: 12)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: grams > 0 ? () => Navigator.of(context).pop(PickResult(_food, _quantity, _unit, grams, _meal)) : null,
            child: Text(widget.actionLabel),
          ),
        ),
      ),
    );
  }
}
