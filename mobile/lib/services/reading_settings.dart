// Who reads a label on the phone: the person's API keys (kept in the Android Keystore, never in the data file or a
// backup) and which model does each step. The app picks sensible defaults from whichever keys are present; the person
// can change any step.
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'llm.dart';

/// The steps that call a model.
enum ReadingStep { firstRead, secondRead, verifier }

extension ReadingStepLabel on ReadingStep {
  String get label => switch (this) {
        ReadingStep.firstRead => 'First read',
        ReadingStep.secondRead => 'Second read',
        ReadingStep.verifier => 'Verifier',
      };

  String get detail => switch (this) {
        ReadingStep.firstRead => 'Transcribes the whole package: name, table, ingredients, category.',
        ReadingStep.secondRead => 'Reads the nutrition table again, on its own, without seeing the first read.',
        ReadingStep.verifier => 'Looks again only at lines the reads or checks are unsure of, and at your notes.',
      };
}

/// One step's model.
class StepChoice {
  const StepChoice(this.provider, this.model, this.effort);

  final LlmProvider provider;
  final String model;
  final String effort;

  StepChoice copyWith({LlmProvider? provider, String? model, String? effort}) =>
      StepChoice(provider ?? this.provider, model ?? this.model, effort ?? this.effort);

  Map<String, Object> toJson() => {'provider': provider.name, 'model': model, 'effort': effort};

  factory StepChoice.fromJson(Map<String, dynamic> j) => StepChoice(
        LlmProvider.values.byName(j['provider'] as String),
        j['model'] as String,
        efforts.contains(j['effort']) ? j['effort'] as String : 'high',
      );

  @override
  bool operator ==(Object other) => other is StepChoice && other.provider == provider && other.model == model && other.effort == effort;

  @override
  int get hashCode => Object.hash(provider, model, effort);
}

/// The defaults: a strong first read, a second read by a different model (the other provider's when both keys are
/// there, so the two reads are as independent as possible), and the most capable model as the verifier, which only
/// runs on what is in doubt.
Map<ReadingStep, StepChoice> defaultSteps(Set<LlmProvider> keys) {
  final a = keys.contains(LlmProvider.anthropic);
  final o = keys.contains(LlmProvider.openai);
  if (a && o) {
    return const {
      ReadingStep.firstRead: StepChoice(LlmProvider.anthropic, 'claude-opus-5-5', 'high'),
      ReadingStep.secondRead: StepChoice(LlmProvider.openai, 'gpt-6.1-sol', 'medium'),
      ReadingStep.verifier: StepChoice(LlmProvider.anthropic, 'claude-fable-5-1', 'high'),
    };
  }
  if (o) {
    return const {
      ReadingStep.firstRead: StepChoice(LlmProvider.openai, 'gpt-6.1-sol', 'high'),
      ReadingStep.secondRead: StepChoice(LlmProvider.openai, 'gpt-6.1-terra', 'medium'),
      ReadingStep.verifier: StepChoice(LlmProvider.openai, 'gpt-6-astra', 'high'),
    };
  }
  return const {
    ReadingStep.firstRead: StepChoice(LlmProvider.anthropic, 'claude-opus-5-5', 'high'),
    ReadingStep.secondRead: StepChoice(LlmProvider.anthropic, 'claude-sonnet-5-5', 'medium'),
    ReadingStep.verifier: StepChoice(LlmProvider.anthropic, 'claude-fable-5-1', 'high'),
  };
}

/// What the person chose, kept in the data file (no secrets). Steps they never changed follow the defaults, which
/// move with the keys they add or remove.
class ReadingSettings {
  const ReadingSettings({this.steps = const {}, this.bar = 90, this.spentUsd = 0});

  /// Steps the person set by hand.
  final Map<ReadingStep, StepChoice> steps;

  /// Lines whose confidence is below this (in percent) need the person's eyes.
  final int bar;

  /// What reading labels has cost so far, in US dollars, across every review.
  final double spentUsd;

  /// The model for [step] given the keys present: the person's choice when its provider has a key, else the default.
  StepChoice choice(ReadingStep step, Set<LlmProvider> keys) {
    final own = steps[step];
    if (own != null && keys.contains(own.provider)) return own;
    return defaultSteps(keys)[step]!;
  }

  ReadingSettings copyWith({Map<ReadingStep, StepChoice>? steps, int? bar, double? spentUsd}) =>
      ReadingSettings(steps: steps ?? this.steps, bar: bar ?? this.bar, spentUsd: spentUsd ?? this.spentUsd);

  Map<String, Object> toJson() => {
        'steps': {for (final e in steps.entries) e.key.name: e.value.toJson()},
        'bar': bar,
        'spentUsd': spentUsd,
      };

  factory ReadingSettings.fromJson(Map<String, dynamic> j) => ReadingSettings(
        steps: {
          for (final e in ((j['steps'] as Map?) ?? const {}).entries)
            if (ReadingStep.values.any((s) => s.name == e.key)) ReadingStep.values.byName(e.key as String): StepChoice.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        bar: (j['bar'] as num?)?.toInt().clamp(50, 100) ?? 90,
        spentUsd: (j['spentUsd'] as num?)?.toDouble() ?? 0,
      );
}

/// The API keys, in the Android Keystore through flutter_secure_storage. [keys] is what the UI listens to.
class ApiKeys {
  ApiKeys._();

  static const _storage = FlutterSecureStorage();
  static String _name(LlmProvider p) => 'api-key-${p.name}';

  static final keys = ValueNotifier<Map<LlmProvider, String>>(const {});

  /// Which providers have a key.
  static Set<LlmProvider> get present => keys.value.keys.toSet();

  static String? of(LlmProvider p) => keys.value[p];

  static Future<void> load() async {
    final out = <LlmProvider, String>{};
    for (final p in LlmProvider.values) {
      try {
        final v = await _storage.read(key: _name(p));
        if (v != null && v.trim().isNotEmpty) out[p] = v.trim();
      } catch (e) {
        debugPrint('Could not read the ${p.label} key: $e');
      }
    }
    keys.value = out;
  }

  static Future<void> save(LlmProvider p, String? key) async {
    final k = key?.trim() ?? '';
    if (k.isEmpty) {
      await _storage.delete(key: _name(p));
      keys.value = {...keys.value}..remove(p);
    } else {
      await _storage.write(key: _name(p), value: k);
      keys.value = {...keys.value, p: k};
    }
  }

  /// For tests.
  @visibleForTesting
  static void setForTest(Map<LlmProvider, String> k) => keys.value = k;
}
