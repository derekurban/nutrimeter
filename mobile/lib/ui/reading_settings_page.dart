// Targets → Label reading: the person's Anthropic and OpenAI keys, which model does each step of a reading, how sure
// a line must be before it is marked off, and what reading has cost so far.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/store.dart';
import '../services/llm.dart';
import '../services/reading_settings.dart';
import 'added_products.dart';
import 'product_flow.dart';
import 'theme.dart';
import 'widgets.dart';

String formatUsd(double usd) => usd < 0.995 ? '${(usd * 100).toStringAsFixed(usd < 0.1 ? 1 : 0)}¢' : '\$${usd.toStringAsFixed(2)}';

/// The card on the settings page.
class LabelReadingCard extends StatelessWidget {
  const LabelReadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: ApiKeys.keys,
      builder: (context, keys, _) {
        final present = keys.keys.toSet();
        final first = state.readingSettings.choice(ReadingStep.firstRead, present);
        final added = state.labelReviews.length;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: Icon(present.isEmpty ? LucideIcons.keyRound : LucideIcons.scanText),
                title: Text(present.isEmpty ? 'Add an API key' : 'Read labels with ${present.map((p) => p.label).join(' and ')}'),
                subtitle: Text(
                  present.isEmpty
                      ? 'New products are read and checked on this phone with your own Anthropic or OpenAI key.'
                      : 'First read by ${modelName(first.model)} · lines under ${state.readingSettings.bar}% need you · ${formatUsd(state.readingSettings.spentUsd)} spent',
                ),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReadingSettingsPage())),
              ),
              if (added > 0)
                ListTile(
                  leading: const Icon(LucideIcons.packageCheck),
                  title: const Text('Added from labels'),
                  subtitle: Text('$added product${added == 1 ? '' : 's'} · what was published'),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddedProductsPage(onOpen: (ctx, r) => resumeReview(ctx, r)))),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ReadingSettingsPage extends StatelessWidget {
  const ReadingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.readingSettings;
    return ValueListenableBuilder(
      valueListenable: ApiKeys.keys,
      builder: (context, keys, _) {
        final present = keys.keys.toSet();
        return Scaffold(
          appBar: AppBar(title: const Text('Label reading')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
            children: [
              Text(
                'When a scan finds nothing, the label is read on this phone with your own key: a first read, a second read by '
                'a different model, arithmetic checks, and a stronger verifier only for lines still in doubt. You settle the rest '
                'against the photos. Keys stay in this phone\'s keystore and are sent only to their provider.',
                style: TextStyle(color: context.muted),
              ),
              const SectionTitle('Keys'),
              for (final p in LlmProvider.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _KeyCard(provider: p, saved: keys[p]),
                ),
              SectionTitle(
                'Models',
                trailing: s.steps.isEmpty
                    ? Text('defaults', style: TextStyle(color: context.muted, fontSize: 12))
                    : TextButton(
                        onPressed: () => state.setReadingSettings(s.copyWith(steps: const {})),
                        child: const Text('Use defaults'),
                      ),
              ),
              if (present.isEmpty)
                Text('Add a key to choose models.', style: TextStyle(color: context.muted))
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [for (final step in ReadingStep.values) _StepTile(step: step, present: present)],
                  ),
                ),
              const SectionTitle('How sure is sure enough'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Lines under ${s.bar}% need you', style: context.text.titleMedium)),
                          Text('${s.bar}%', style: context.text.titleLarge?.copyWith(fontFeatures: tabular)),
                        ],
                      ),
                      Slider(
                        value: s.bar.toDouble(),
                        min: 70,
                        max: 100,
                        divisions: 30,
                        label: '${s.bar}%',
                        onChanged: (v) => state.setReadingSettings(s.copyWith(bar: v.round())),
                      ),
                      Text(
                        'Two reads that agree score 99%. A disagreement starts at 45% and the verifier lifts it once it reads the photo '
                        'clearly. Raise the bar to look at more lines yourself; at 100% you confirm every line.',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Spending'),
              Card(
                child: ListTile(
                  leading: const Icon(LucideIcons.receipt),
                  title: Text('${formatUsd(s.spentUsd)} spent on reading labels'),
                  subtitle: const Text('From the tokens each provider reported, at published prices. Your provider\'s bill is the final word.'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.provider, required this.saved});

  final LlmProvider provider;
  final String? saved;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  final _key = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  String get _hint => widget.provider == LlmProvider.anthropic ? 'sk-ant-…' : 'sk-…';

  Future<void> _test(String key) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final models = await listModels(widget.provider, key);
      final known = knownModels.where((m) => m.provider == widget.provider && models.contains(m.id)).map((m) => m.name).toList();
      setState(() {
        _ok = true;
        _status = 'The key works. ${known.isEmpty ? '${models.length} models available.' : 'Available: ${known.join(', ')}.'}';
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final k = _key.text.trim();
    if (k.isEmpty) return;
    await _test(k);
    if (!_ok) return;
    await ApiKeys.save(widget.provider, k);
    if (!mounted) return;
    setState(() => _editing = false);
    _key.clear();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.saved;
    final du = context.du;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.provider.label, style: context.text.titleMedium)),
                if (saved != null && !_editing) ...[
                  TextButton(onPressed: _busy ? null : () => _test(saved), child: Text(_busy ? 'Testing…' : 'Test')),
                  TextButton(onPressed: () => setState(() => _editing = true), child: const Text('Replace')),
                  IconButton(
                    icon: const Icon(LucideIcons.trash2),
                    tooltip: 'Remove key',
                    onPressed: () async {
                      if (await confirmDialog(
                        context,
                        'Remove the ${widget.provider.label} key?',
                        'Steps that use it fall back to your other key, if any.',
                        action: 'Remove',
                      )) {
                        await ApiKeys.save(widget.provider, null);
                        setState(() => _status = null);
                      }
                    },
                  ),
                ],
              ],
            ),
            if (saved != null && !_editing)
              Text('Saved · ends in ${saved.substring(saved.length - 4)}', style: TextStyle(color: context.muted))
            else ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: '${widget.provider.label} API key', hintText: _hint),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_editing) TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Checking…' : 'Check and save')),
                  ),
                ],
              ),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(_status!, style: TextStyle(color: _ok ? du.accentText : du.danger, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.present});

  final ReadingStep step;
  final Set<LlmProvider> present;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.readingSettings;
    final c = s.choice(step, present);
    final custom = s.steps[step] != null && present.contains(s.steps[step]!.provider);
    final m = knownModel(c.model);
    return ListTile(
      title: Text(step.label),
      subtitle: Text(
        '${modelName(c.model)} · ${c.effort} effort${custom ? '' : ' · default'}\n${step.detail}'
        '${m == null ? '' : '\n\$${m.inputPerM} in / \$${m.outputPerM} out per million tokens'}',
      ),
      isThreeLine: true,
      trailing: const Icon(LucideIcons.pencil, size: 18),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => AppScope(
          state: state,
          child: _StepSheet(step: step, present: present, initial: c),
        ),
      ),
    );
  }
}

class _StepSheet extends StatefulWidget {
  const _StepSheet({required this.step, required this.present, required this.initial});

  final ReadingStep step;
  final Set<LlmProvider> present;
  final StepChoice initial;

  @override
  State<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends State<_StepSheet> {
  late StepChoice _c = widget.initial;
  late final _other = TextEditingController(text: knownModel(widget.initial.model) == null ? widget.initial.model : '');

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _save() {
    final state = AppScope.read(context);
    final typed = _other.text.trim();
    final choice = typed.isNotEmpty && knownModel(_c.model) == null ? _c.copyWith(model: typed) : _c;
    state.setReadingSettings(state.readingSettings.copyWith(steps: {...state.readingSettings.steps, widget.step: choice}));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final models = knownModels.where((m) => m.provider == _c.provider).toList();
    final isOther = knownModel(_c.model) == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.step.label, style: context.text.titleLarge),
            Text(widget.step.detail, style: TextStyle(color: context.muted)),
            const SizedBox(height: 14),
            if (widget.present.length > 1)
              SegmentedButton<LlmProvider>(
                segments: [for (final p in LlmProvider.values) ButtonSegment(value: p, label: Text(p.label))],
                selected: {_c.provider},
                onSelectionChanged: (v) => setState(() {
                  final p = v.first;
                  _c = StepChoice(p, knownModels.firstWhere((m) => m.provider == p && m.inputPerM >= 2).id, _c.effort);
                }),
              ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: isOther ? '' : _c.model,
              onChanged: (v) => setState(() => _c = _c.copyWith(model: v ?? '')),
              child: Column(
                children: [
                  for (final m in models)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: m.id,
                      title: Text(m.name),
                      subtitle: Text('${m.note} · \$${m.inputPerM} / \$${m.outputPerM} per M tokens'),
                    ),
                  RadioListTile<String>(contentPadding: EdgeInsets.zero, value: '', title: const Text('Another model')),
                ],
              ),
            ),
            if (isOther)
              TextField(
                controller: _other,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Model id', hintText: 'as your provider names it'),
              ),
            const SizedBox(height: 14),
            Text('Effort', style: context.text.labelLarge?.copyWith(color: context.muted)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                for (final e in ['low', 'medium', 'high', 'xhigh']) ButtonSegment(value: e, label: Text(e)),
              ],
              selected: {efforts.contains(_c.effort) && _c.effort != 'max' ? _c.effort : 'high'},
              onSelectionChanged: (v) => setState(() => _c = _c.copyWith(effort: v.first)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
