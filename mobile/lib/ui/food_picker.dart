import 'package:flutter/material.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/foods.dart';
import '../services/off.dart';
import 'custom_foods.dart';
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

/// Generic foods (CNF), your own foods and recipes are searched on the device as you type.
/// Open Food Facts is only asked when you submit, or scan a barcode.
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

  String? _offQuery;
  List<Food> _offFoods = [];
  int _offPage = 1;
  bool _offMore = false;
  bool _offLoading = false;
  String? _offError;

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

  Future<void> _searchOff({bool more = false}) async {
    final q = _q.trim();
    if (q.isEmpty) return;
    if (OpenFoodFacts.isBarcode(q)) return _lookupBarcode(q);
    final page = more ? _offPage + 1 : 1;
    setState(() {
      _offLoading = true;
      _offError = null;
      if (!more) {
        _offQuery = q;
        _offFoods = [];
      }
    });
    try {
      final res = await AppScope.read(context).off.search(q, page: page);
      if (!mounted) return;
      setState(() {
        _offFoods = more ? [..._offFoods, ...res.foods] : res.foods;
        _offPage = page;
        _offMore = res.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _offError = '$e');
    } finally {
      if (mounted) setState(() => _offLoading = false);
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _query.text = code;
    setState(() => _q = code);
    await _lookupBarcode(code);
  }

  Future<void> _lookupBarcode(String code) async {
    final state = AppScope.read(context);
    setState(() {
      _offLoading = true;
      _offError = null;
      _offQuery = code;
      _offFoods = [];
    });
    Food? food;
    try {
      food = await state.off.product(code);
    } catch (e) {
      if (mounted) setState(() => _offError = '$e');
      return;
    } finally {
      if (mounted) setState(() => _offLoading = false);
    }
    if (!mounted) return;
    if (food == null) {
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Not in Open Food Facts'),
          content: Text('No product has the barcode $code yet. You can add it as a custom food from its nutrition label.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create custom food')),
          ],
        ),
      );
      if (create == true && mounted) {
        final created = await editCustomFood(context, barcode: code);
        if (created != null && mounted) await _open(created);
      }
      return;
    }
    state.cacheFood(food);
    setState(() => _offFoods = [food!]);
    await _open(food);
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
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear',
                      onPressed: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                    ),
            ),
            onChanged: (s) => setState(() => _q = s),
            onSubmitted: (_) => _searchOff(),
          ),
          actions: [IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan barcode', onPressed: _scan)],
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'All'),
            Tab(text: 'History'),
            Tab(text: 'My foods'),
            Tab(text: 'Recipes'),
          ]),
        ),
        body: TabBarView(children: [
          _allTab(state),
          _list(state.recentFoods.where(_matches).toList(), empty: 'Foods you log show up here.'),
          _list(state.activeCustomFoods.where(_matches).toList(), empty: 'No custom foods yet. Create them from the Foods tab.'),
          _list([for (final r in state.activeRecipes) recipeAsFood(state, r)].where(_matches).toList(),
              empty: 'No recipes yet. Build one from the Recipes tab.'),
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
            'Type to search generic foods (Canadian Nutrient File) and your own foods. '
            'Press search on the keyboard to look in Open Food Facts for packaged products, or scan a barcode.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted),
          ),
        ),
      ]);
    }
    final mine = [...state.activeCustomFoods, for (final r in state.activeRecipes) recipeAsFood(state, r)].where(_matches).toList();
    final generic = state.cnf.search(q).where((f) => !widget.exclude.contains(f.id)).toList();
    final offShown = _offQuery == q;
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      if (mine.isNotEmpty) ...[
        const _Header('My foods & recipes'),
        for (final f in mine) _FoodTile(food: f, onTap: () => _open(f)),
      ],
      _Header('Generic foods · Canadian Nutrient File', trailing: !state.cnfReady ? 'loading…' : generic.isEmpty ? 'no matches' : null),
      for (final f in generic) _FoodTile(food: f, onTap: () => _open(f)),
      const _Header('Packaged products · Open Food Facts'),
      if (_offError != null)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(_offError!, style: const TextStyle(color: Palette.danger))),
      if (offShown) ...[
        for (final f in _offFoods.where((f) => !widget.exclude.contains(f.id))) _FoodTile(food: f, onTap: () => _open(f)),
        if (!_offLoading && _offFoods.isEmpty && _offError == null)
          Padding(padding: const EdgeInsets.all(16), child: Text('No products with nutrition data matched.', style: TextStyle(color: context.muted))),
        if (_offMore && !_offLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(onPressed: () => _searchOff(more: true), child: const Text('Load more')),
          ),
      ],
      if (_offLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (!offShown && !_offLoading)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: OutlinedButton.icon(
            icon: Icon(OpenFoodFacts.isBarcode(q) ? Icons.qr_code : Icons.search),
            label: Text(OpenFoodFacts.isBarcode(q) ? 'Look up barcode $q' : 'Search Open Food Facts for “$q”'),
            onPressed: _searchOff,
          ),
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
