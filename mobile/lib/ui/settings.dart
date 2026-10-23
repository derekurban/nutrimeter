import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';

import '../data/model.dart';
import '../data/nutrients.dart';
import '../data/store.dart';
import '../logic/targets.dart';
import '../version.dart';
import 'theme.dart';
import 'updates.dart';
import 'widgets.dart';

/// The Updates section, for the banner's "Go to update".
final _updates = GlobalKey();

/// Profile, energy and macro targets, per-nutrient overrides, data, updates, feedback and attribution.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.targets;
    final p = t.profile;
    final kcal = energyTarget(t);
    void setProfile(Profile profile) => state.setTargets(t.copyWith(profile: profile));
    final macroSum = t.macros.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Targets & settings')),
      // Built in full, not lazily, so the banner can scroll to the Updates section at the bottom.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          UpdateBanner(onGo: () => Scrollable.ensureVisible(_updates.currentContext!, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic)),
          const SectionTitle('Profile'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<Sex>(
                  segments: const [ButtonSegment(value: Sex.male, label: Text('Male')), ButtonSegment(value: Sex.female, label: Text('Female'))],
                  selected: {p.sex},
                  onSelectionChanged: (s) => setProfile(p.copyWith(sex: s.first)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _NumberField(label: 'Age', value: p.age.toDouble(), onChanged: (v) => setProfile(p.copyWith(age: v.round())))),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Weight', suffix: 'kg', value: p.weightKg, onChanged: (v) => setProfile(p.copyWith(weightKg: v)))),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Height', suffix: 'cm', value: p.heightCm, onChanged: (v) => setProfile(p.copyWith(heightCm: v)))),
                ]),
                const SizedBox(height: 14),
                DropdownButtonFormField<double>(
                  initialValue: p.activity,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Activity'),
                  items: [for (final (v, label) in activityLevels) DropdownMenuItem(value: v, child: Text(label))],
                  onChanged: (v) => setProfile(p.copyWith(activity: v)),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: p.goalDelta,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Goal'),
                  items: [
                    for (final (v, label) in goalOptions) DropdownMenuItem(value: v, child: Text(v == 0 ? label : '$label (${v > 0 ? '+' : ''}$v kcal)')),
                  ],
                  onChanged: (v) => setProfile(p.copyWith(goalDelta: v)),
                ),
              ]),
            ),
          ),
          const SectionTitle('Energy'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set calories manually'),
                  value: t.manualKcal != null,
                  onChanged: (on) => state.setTargets(t.copyWith(manualKcal: () => on ? kcal : null)),
                ),
                if (t.manualKcal != null)
                  _NumberField(label: 'Daily energy', suffix: 'kcal', value: t.manualKcal!.toDouble(), onChanged: (v) => state.setTargets(t.copyWith(manualKcal: () => v.round())))
                else ...[
                  _Stat('BMR (Mifflin–St Jeor)', '${bmr(p).round()} kcal'),
                  _Stat('× activity ${p.activity}', '${(bmr(p) * p.activity).round()} kcal'),
                  _Stat('Goal adjustment', '${p.goalDelta > 0 ? '+' : ''}${p.goalDelta} kcal'),
                  const Divider(),
                  _Stat('Daily target', '$kcal kcal', bold: true),
                ],
              ]),
            ),
          ),
          const SectionTitle('Macro split'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      for (final m in macroKeys)
                        if ((t.macros[m] ?? 0) > 0) Expanded(flex: t.macros[m]!, child: Container(color: context.du.macro(m))),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                for (final m in macroKeys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: context.du.macro(m), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(macroLabels[m]!)),
                      SizedBox(
                        width: 90,
                        child: _NumberField(
                          label: '',
                          suffix: '%',
                          value: (t.macros[m] ?? 0).toDouble(),
                          onChanged: (v) => state.setTargets(t.copyWith(macros: {...t.macros, m: v.round().clamp(0, 100)})),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text('${(kcal * (t.macros[m] ?? 0) / 100 / kcalPerGram[m]!).round()} g', textAlign: TextAlign.right, style: TextStyle(color: context.muted)),
                      ),
                    ]),
                  ),
                if (macroSum != 100)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('These add up to $macroSum%. Adjust them to total 100%.', style: TextStyle(color: context.du.danger)),
                  ),
              ]),
            ),
          ),
          SectionTitle('Nutrient targets', trailing: Text('tap to change', style: TextStyle(color: context.muted, fontSize: 12))),
          for (final group in NutrientGroup.values) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text(group.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final def in nutrients.where((n) => n.group == group && n.key != 'energy' && !n.derived))
                  _OverrideTile(def: def),
              ]),
            ),
          ],
          const SectionTitle('Your data'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              ListTile(
                leading: const Icon(LucideIcons.upload),
                title: const Text('Export backup'),
                subtitle: const Text('Copies all your data to the clipboard as JSON'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: state.exportJson()));
                  if (context.mounted) showToast(context, 'Backup copied to the clipboard');
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.download),
                title: const Text('Import backup'),
                subtitle: const Text('Replaces everything with a backup from the clipboard'),
                onTap: () async {
                  final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                  if (!context.mounted) return;
                  if (raw == null || raw.isEmpty) return showToast(context, 'The clipboard is empty');
                  if (!await confirmDialog(context, 'Replace all data?', 'Your diary, foods, recipes and targets are replaced by the backup.', action: 'Replace')) return;
                  try {
                    state.importJson(raw);
                    if (context.mounted) showToast(context, 'Backup restored');
                  } catch (e) {
                    if (context.mounted) showToast(context, 'That is not a Nutrimeter backup');
                  }
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.trash2, color: context.du.danger),
                title: const Text('Reset everything'),
                onTap: () async {
                  if (await confirmDialog(context, 'Delete all data?', 'Removes every diary entry, food, recipe and target. This cannot be undone.')) {
                    state.resetAll();
                  }
                },
              ),
            ]),
          ),
          ValueListenableBuilder(
            valueListenable: updateAvailable,
            builder: (_, r, _) => SectionTitle('Updates', key: _updates, trailing: r == null ? null : const UpdateDot()),
          ),
          const UpdatePanel(),
          const SectionTitle('Feedback'),
          const FeedbackCard(),
          const SectionTitle('About'),
          Text('$appName $appVersion · open source under GPL-3.0\n$repoUrl', style: TextStyle(color: context.muted)),
          const SizedBox(height: 10),
          Text(
            'Packaged food data © Open Food Facts contributors, available under the Open Database License (ODbL). '
            'Product images under CC BY-SA.',
            style: TextStyle(color: context.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.cnf.attribution.isEmpty ? 'Canadian Nutrient File, Health Canada.' : state.cnf.attribution} '
            'Omega-3 and omega-6 totals are summed from individual fatty acids; values are rounded to 4 significant digits.',
            style: TextStyle(color: context.muted, fontSize: 12.5),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? null : context.muted, fontWeight: bold ? FontWeight.w600 : null))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w600 : null)),
        ]),
      );
}

/// A numeric field that reports valid values as they're typed.
class _NumberField extends StatefulWidget {
  const _NumberField({required this.label, required this.value, required this.onChanged, this.suffix});

  final String label;
  final double value;
  final String? suffix;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _c = TextEditingController(text: formatAmount(widget.value));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: widget.label.isEmpty ? null : widget.label, suffixText: widget.suffix),
        onChanged: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          if (v != null) widget.onChanged(v);
        },
      );
}

class _OverrideTile extends StatelessWidget {
  const _OverrideTile({required this.def});

  final NutrientDef def;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final o = state.targets.overrides[def.key];
    final r = state.resolvedTargets[def.key]!;
    final parts = [
      if (r.target != null) 'target ${formatAmount(r.target, def.unit)} ${def.unit}',
      if (r.max != null) 'max ${formatAmount(r.max, def.unit)} ${def.unit}',
    ];
    return ListTile(
      dense: true,
      title: Text(def.label),
      subtitle: Text(parts.isEmpty ? 'no target' : parts.join(' · ')),
      trailing: o == null ? null : Icon(LucideIcons.pencil, size: 16, color: context.du.accentText),
      onTap: () => _edit(context, state),
    );
  }

  Future<void> _edit(BuildContext context, AppState state) async {
    final defaults = defaultTargets(state.targets)[def.key]!;
    final o = state.targets.overrides[def.key];
    final target = TextEditingController(text: o?.target == null ? '' : formatAmount(o!.target));
    final max = TextEditingController(text: o?.max == null ? '' : formatAmount(o!.max));
    double? parse(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def.label),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Daily target', suffixText: def.unit, hintText: defaults.target == null ? 'none' : 'default ${formatAmount(defaults.target, def.unit)}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Upper limit', suffixText: def.unit, hintText: defaults.max == null ? 'none' : 'default ${formatAmount(defaults.max, def.unit)}'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Use defaults')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    final next = TargetOverride(target: parse(target), max: parse(max));
    target.dispose();
    max.dispose();
    if (result == null) return;
    final overrides = {...state.targets.overrides};
    if (result == 'reset' || next.isEmpty) {
      overrides.remove(def.key);
    } else {
      overrides[def.key] = next;
    }
    state.setTargets(state.targets.copyWith(overrides: overrides));
  }
}
