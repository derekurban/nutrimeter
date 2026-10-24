import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/barcode.dart';
import '../logic/foods.dart';
import '../services/backend.dart';
import 'capture.dart';
import 'food_detail.dart';
import 'scanner.dart';
import 'theme.dart';
import 'widgets.dart';

/// Search every source, pick a food and an amount. Returns null if cancelled.
Future<PickResult?> pickFood(
  BuildContext context, {
  required String title,
  required String actionLabel,
  Meal? meal,
  Set<String> exclude = const {},
  bool scan = false,
}) =>
    Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodPickerPage(title: title, actionLabel: actionLabel, meal: meal, exclude: exclude, scanFirst: scan),
    ));

/// Everything is searched on the device as you type: your foods and recipes, the synced catalogue, products waiting
/// for review, and generic foods (CNF). A barcode is looked up in the catalogue, then your saved foods; a miss (or a
/// product still waiting for review) is checked against a fresh catalogue before anything else. Anything not found
/// can be added from photos and logged at once.
class FoodPickerPage extends StatefulWidget {
  const FoodPickerPage({super.key, required this.title, required this.actionLabel, this.meal, this.exclude = const {}, this.scanFirst = false});

  final String title;
  final String actionLabel;
  final Meal? meal;
  final Set<String> exclude;
  final bool scanFirst;

  @override
  State<FoodPickerPage> createState() => _FoodPickerPageState();
}

class _FoodPickerPageState extends State<FoodPickerPage> {
  final _query = TextEditingController();
  String _q = '';
  String? _barcodeError;

  /// A barcode lookup is checking the catalogue.
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    if (widget.scanFirst) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Food f) {
    if (widget.exclude.contains(f.id)) return false;
    final hay = '${f.name} ${f.brand ?? ''}'.toLowerCase();
    return _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(hay.contains);
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _query.text = code.raw;
    setState(() => _q = code.raw);
    await _lookup(code);
  }

  /// A barcode typed into search.
  Future<void> _lookupTyped(String q) async {
    final code = normalizeBarcode(q, Symbology.unknown);
    if (code == null) {
      setState(() => _barcodeError = '$q is not a valid barcode (its check digit does not match).');
      return;
    }
    await _lookup(code);
  }

  Future<void> _lookup(Gtin code) async {
    if (_looking) return;
    final state = AppScope.read(context);
    setState(() {
      _barcodeError = null;
      _looking = true;
    });
    final Food? food;
    try {
      food = await state.lookupBarcode(code.gtin14, refresh: Backend.signedIn ? () => Backend.sync(state, force: true) : null);
    } finally {
      if (mounted) setState(() => _looking = false);
    }
    if (!mounted) return;
    if (food != null) return _open(food);
    await _addProduct(barcode: code);
  }

  Future<void> _addProduct({Gtin? barcode, String? name}) async {
    final food = await captureProduct(context, barcode: barcode, nameHint: name);
    if (food != null && mounted) await _open(food);
  }

  Future<void> _open(Food food) async {
    final result = await Navigator.of(context).push<PickResult>(MaterialPageRoute(
      builder: (_) => FoodDetailPage(food: food, actionLabel: widget.actionLabel, meal: widget.meal),
    ));
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _query,
            autofocus: !widget.scanFirst,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search foods or enter a barcode',
              border: InputBorder.none,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x),
                      tooltip: 'Clear',
                      onPressed: () {
                        _query.clear();
                        setState(() {
                          _q = '';
                          _barcodeError = null;
                        });
                      },
                    ),
            ),
            onChanged: (s) => setState(() {
              _q = s;
              _barcodeError = null;
            }),
            onSubmitted: (s) {
              if (looksLikeBarcode(s)) _lookupTyped(s.trim());
            },
          ),
          actions: [IconButton(icon: const Icon(LucideIcons.scanBarcode), tooltip: 'Scan barcode', onPressed: _scan)],
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'All'),
            Tab(text: 'History'),
            Tab(text: 'My foods'),
            Tab(text: 'Recipes'),
          ]),
        ),
        body: Column(children: [
          if (_looking) const LinearProgressIndicator(semanticsLabel: 'Looking up the barcode'),
          Expanded(
            child: TabBarView(children: [
              _allTab(state),
              _list(state.recentFoods.where(_matches).toList(), empty: 'Foods you log show up here.'),
              _list(state.activeCustomFoods.where(_matches).toList(), empty: 'No custom foods yet. Create them from the Foods tab.'),
              _list([for (final r in state.activeRecipes) recipeAsFood(state, r)].where(_matches).toList(),
                  empty: 'No recipes yet. Build one from the Recipes tab.'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _allTab(AppState state) {
    final q = _q.trim();
    if (q.isEmpty) {
      final recent = state.recentFoods.where(_matches).take(20).toList();
      return ListView(children: [
        if (recent.isNotEmpty) const _Header('Recent'),
        for (final f in recent) _FoodTile(food: f, onTap: () => _open(f)),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Type to search products, generic foods and your own foods, or scan a barcode. '
            'Something missing can be added from photos of its package and logged straight away.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted),
          ),
        ),
      ]);
    }
    final barcode = looksLikeBarcode(q);
    final mine = [...state.activeCustomFoods, for (final r in state.activeRecipes) recipeAsFood(state, r)].where(_matches).toList();
    final products = [
      ...state.catalogue.search(q).where((f) => !widget.exclude.contains(f.id)),
      ...state.provisionalFoods.where(_matches),
    ];
    final generic = state.cnf.search(q).where((f) => !widget.exclude.contains(f.id)).toList();
    final nothing = mine.isEmpty && products.isEmpty && generic.isEmpty && state.cnfReady;
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      if (barcode) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: OutlinedButton.icon(
            icon: const Icon(LucideIcons.barcode),
            label: Text('Look up barcode $q'),
            onPressed: () => _lookupTyped(q),
          ),
        ),
        if (_barcodeError != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(_barcodeError!, style: TextStyle(color: context.du.danger))),
      ],
      if (mine.isNotEmpty) ...[
        const _Header('My foods & recipes'),
        for (final f in mine) _FoodTile(food: f, onTap: () => _open(f)),
      ],
      if (products.isNotEmpty) ...[
        const _Header('Products'),
        for (final f in products) _FoodTile(food: f, onTap: () => _open(f)),
      ],
      if (!barcode) ...[
        _Header('Generic foods · Canadian Nutrient File', trailing: !state.cnfReady ? 'loading…' : generic.isEmpty ? 'no matches' : null),
        for (final f in generic) _FoodTile(food: f, onTap: () => _open(f)),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            nothing ? 'Nothing matches “$q”.' : 'Not what you are looking for?',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.camera),
            label: const Text('Add a product'),
            onPressed: () => barcode ? _lookupTyped(q) : _addProduct(name: q),
          ),
        ]),
      ),
    ]);
  }

  Widget _list(List<Food> foods, {required String empty}) => foods.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: context.muted))))
      : ListView(children: [for (final f in foods) _FoodTile(food: f, onTap: () => _open(f))]);
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          Expanded(child: Text(text, style: context.text.labelLarge?.copyWith(color: context.muted, fontWeight: FontWeight.w600))),
          if (trailing != null) Text(trailing!, style: TextStyle(color: context.muted, fontSize: 12)),
        ]),
      );
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.onTap});

  final Food food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kcal = food.nutrients['energy'];
    final serving = food.servings.isEmpty ? null : food.servings.first;
    final energy = serving != null && kcal != null
        ? '${formatAmount(kcal * serving.grams / 100, 'kcal')} kcal / ${serving.label}'
        : kcal != null
            ? '${formatAmount(kcal, 'kcal')} kcal / 100 g'
            : food.source.isProvisional
                ? 'nutrition after review'
                : 'no nutrition data';
    return ListTile(
      leading: FoodThumb(food: food),
      title: Text(food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([?food.brand, energy].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: SourceBadge(food.source),
      onTap: onTap,
    );
  }
}
