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
  late final Food _food = widget.food;
  late double _quantity;
  late String _unit;
  late Meal? _meal = widget.meal;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantity != null && widget.initialUnit != null) {
      _quantity = widget.initialQuantity!;
      _unit = widget.initialUnit!;
    } else {
      _applyDefault(_food);
    }
  }

  void _applyDefault(Food food) {
    final d = defaultServing(food);
    _quantity = d.quantity;
    _unit = d.unit.label;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final grams = gramsFor(_food, _quantity, _unit);
    final scaled = withDerived(scaleTo(_food.nutrients, grams));
    final category = _food.source == FoodSource.catalogue ? state.catalogue.categoryLabel(_food.id) : null;
    return Scaffold(
      appBar: AppBar(title: Text(_food.source.label, style: context.text.titleMedium)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FoodThumb(food: _food, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_food.name, style: context.text.headlineMedium),
              if (category != null) Text(category, style: TextStyle(color: context.muted, fontSize: 12)),
              if (_food.brand != null) Text(_food.brand!, style: TextStyle(color: context.muted)),
              if (_food.barcode != null) Text(_food.barcode!, style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
          ),
        ]),
        if (!_food.hasNutrition)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.du.warningSubtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.du.warningLine, width: 0.6)),
            child: Text(_food.source.isProvisional
                ? 'This product is waiting for review. Log it by weight now; its nutrition fills in once the label is reviewed.'
                : 'This food has no nutrition data.'),
          ),
        const SizedBox(height: 18),
        ServingField(
          food: _food,
          quantity: _quantity,
          unit: _unit,
          autofocus: widget.initialQuantity != null,
          onChanged: (q, u) => setState(() {
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
