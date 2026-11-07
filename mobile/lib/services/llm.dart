// Reading labels with the person's own API key: one structured request to Anthropic's Messages API or OpenAI's
// Responses API, photos attached, the answer constrained to a JSON schema. No SDK exists for Dart, so this is plain
// HTTP. Schemas passed here use no unions and no optional properties (every field is required, "unknown" is an
// empty string or -1), which keeps them inside Anthropic's structured-output limits and OpenAI's strict mode alike.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum LlmProvider { anthropic, openai }

extension LlmProviderLabel on LlmProvider {
  String get label => switch (this) { LlmProvider.anthropic => 'Anthropic', LlmProvider.openai => 'OpenAI' };
}

/// A model the app knows: its provider, a readable name, what it costs per million tokens, and a one-line note.
class LlmModel {
  const LlmModel(this.provider, this.id, this.name, this.inputPerM, this.outputPerM, this.note);

  final LlmProvider provider;
  final String id;
  final String name;
  final double inputPerM;
  final double outputPerM;
  final String note;
}

/// Prices as published in November 2026. A model typed in by hand that is not here still works; its cost shows as
/// unknown.
const knownModels = <LlmModel>[
  LlmModel(LlmProvider.anthropic, 'claude-fable-5-1', 'Claude Fable 5.1', 10, 50, 'Anthropic\'s most capable model'),
  LlmModel(LlmProvider.anthropic, 'claude-opus-5-5', 'Claude Opus 5.5', 4, 20, 'Strong reader, moderate cost'),
  LlmModel(LlmProvider.anthropic, 'claude-sonnet-5-5', 'Claude Sonnet 5.5', 2, 10, 'Fast and capable'),
  LlmModel(LlmProvider.anthropic, 'claude-haiku-5-5', 'Claude Haiku 5.5', 0.1, 0.5, 'Cheapest, least careful'),
  LlmModel(LlmProvider.openai, 'gpt-6-astra', 'GPT-6 Astra', 10, 50, 'OpenAI\'s flagship'),
  LlmModel(LlmProvider.openai, 'gpt-6.1-sol', 'GPT-6.1 Sol', 2, 10, 'Balanced intelligence and cost'),
  LlmModel(LlmProvider.openai, 'gpt-6.1-terra', 'GPT-6.1 Terra', 1, 5, 'Fast and efficient'),
  LlmModel(LlmProvider.openai, 'gpt-6-luna', 'GPT-6 Luna', 0.1, 0.5, 'Cheapest, least careful'),
];

LlmModel? knownModel(String id) => knownModels.where((m) => m.id == id).firstOrNull;

String modelName(String id) => knownModel(id)?.name ?? id;

/// Reasoning effort, the same five words on both providers.
const efforts = ['low', 'medium', 'high', 'xhigh', 'max'];

/// One image attached to a request.
class LlmImage {
  const LlmImage(this.bytes, this.mediaType);

  final List<int> bytes;
  final String mediaType;
}

/// What a request returned: the parsed JSON object, the tokens it used and what that cost (null when the model's
/// price is not known), and the model that actually answered (a fallback can differ from the one asked for).
class LlmResult {
  const LlmResult({required this.json, required this.model, required this.inputTokens, required this.outputTokens, required this.ms});

  final Map<String, dynamic> json;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int ms;

  double? get costUsd => costOf(model, inputTokens, outputTokens);
}

double? costOf(String model, int inputTokens, int outputTokens) {
  final m = knownModel(model);
  if (m == null) return null;
  return (inputTokens * m.inputPerM + outputTokens * m.outputPerM) / 1e6;
}

/// A request that failed. [retryable] for rate limits, overload, timeouts and a lost connection; [keyProblem] when the
/// key itself was refused.
class LlmException implements Exception {
  const LlmException(this.message, {this.retryable = false, this.keyProblem = false});

  final String message;
  final bool retryable;
  final bool keyProblem;

  @override
  String toString() => message;
}

/// Sends one request and returns its JSON answer. [schema] is the answer's JSON schema, named [schemaName].
Future<LlmResult> callLlm({
  required LlmProvider provider,
  required String apiKey,
  required String model,
  required String effort,
  required String system,
  required String text,
  required List<LlmImage> images,
  required Map<String, dynamic> schema,
  required String schemaName,
  http.Client? client,
  Duration timeout = const Duration(minutes: 9),
}) async {
  final c = client ?? http.Client();
  final watch = Stopwatch()..start();
  try {
    final r = switch (provider) {
      LlmProvider.anthropic => await _anthropicWithFallback(c, apiKey, model, effort, system, text, images, schema).timeout(timeout),
      LlmProvider.openai => await _openai(c, apiKey, model, effort, system, text, images, schema, schemaName).timeout(timeout),
    };
    return LlmResult(json: r.$1, model: r.$2, inputTokens: r.$3, outputTokens: r.$4, ms: watch.elapsedMilliseconds);
  } on TimeoutException {
    throw const LlmException('The model took too long to answer.', retryable: true);
  } on SocketException {
    throw const LlmException('No connection.', retryable: true);
  } on http.ClientException catch (e) {
    throw LlmException('Connection failed: ${e.message}', retryable: true);
  } finally {
    if (client == null) c.close();
  }
}

/// Models whose requests opt into Anthropic's server-side fallback on a refusal (a food label should never trip a
/// safety classifier, but a false positive then still gets an answer).
const _withFallback = {'claude-fable-5-1', 'claude-opus-5-5', 'claude-sonnet-5-5'};

/// Anthropic refuses a schema whose compiled grammar is too large. Then the request goes again without the format
/// constraint, the schema in the instructions instead, and the answer is parsed (and checked by the caller) as JSON.
Future<(Map<String, dynamic>, String, int, int)> _anthropicWithFallback(http.Client c, String key, String model, String effort, String system,
    String text, List<LlmImage> images, Map<String, dynamic> schema) async {
  try {
    return await _anthropic(c, key, model, effort, system, text, images, schema);
  } on LlmException catch (e) {
    if (!schemaRefused(e.message)) rethrow;
    return _anthropic(c, key, model, effort, system, text, images, schema, constrained: false);
  }
}

/// The error Anthropic gives for a schema it will not compile.
bool schemaRefused(String message) =>
    RegExp(r'grammar is too large|too complex for compilation|schema.*(too complex|not supported|unsupported)', caseSensitive: false).hasMatch(message);

Future<(Map<String, dynamic>, String, int, int)> _anthropic(http.Client c, String key, String model, String effort, String system,
    String text, List<LlmImage> images, Map<String, dynamic> schema, {bool constrained = true}) async {
  final fallback = _withFallback.contains(model);
  final body = {
    'model': model,
    'max_tokens': 32000,
    'system': constrained
        ? system
        : '$system\n\nAnswer with one JSON object and nothing else: no prose, no code fence. It must match this JSON schema '
            'exactly, with every property present:\n${jsonEncode(schema)}',
    'output_config': {
      'effort': effort,
      if (constrained) 'format': {'type': 'json_schema', 'schema': schema},
    },
    'fallbacks': ?(fallback ? 'default' : null),
    'messages': [
      {
        'role': 'user',
        'content': [
          for (final i in images) {'type': 'image', 'source': {'type': 'base64', 'media_type': i.mediaType, 'data': base64Encode(i.bytes)}},
          {'type': 'text', 'text': text},
        ],
      },
    ],
  };
  // Streamed: a careful first read can think for minutes, and a long answer must not meet a non-streaming limit.
  final req = http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
    ..headers.addAll({
      'content-type': 'application/json',
      'x-api-key': key,
      'anthropic-version': '2026-10-21',
      if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    })
    ..body = jsonEncode({...body, 'stream': true});
  final res = await c.send(req);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    _decode(await http.Response.fromStream(res), LlmProvider.anthropic);
  }
  final answer = StringBuffer();
  var answered = model;
  var input = 0, output = 0;
  String? stop;
  await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.startsWith('data:')) continue;
    final Map<String, dynamic> e;
    try {
      e = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    switch (e['type']) {
      case 'message_start':
        final m = (e['message'] as Map?) ?? const {};
        answered = (m['model'] as String?) ?? answered;
        final u = (m['usage'] as Map?) ?? const {};
        input = ((u['input_tokens'] as num?) ?? 0).toInt() + ((u['cache_read_input_tokens'] as num?) ?? 0).toInt();
      case 'content_block_start':
        // A fallback model takes over: its text replaces whatever the declined model wrote.
        if ((e['content_block'] as Map?)?['type'] == 'fallback') {
          answer.clear();
          answered = ((e['content_block'] as Map)['to'] as Map?)?['model'] as String? ?? answered;
        }
      case 'content_block_delta':
        final d = (e['delta'] as Map?) ?? const {};
        if (d['type'] == 'text_delta') answer.write(d['text']);
      case 'message_delta':
        stop = ((e['delta'] as Map?)?['stop_reason'] as String?) ?? stop;
        final u = (e['usage'] as Map?) ?? const {};
        output = ((u['output_tokens'] as num?) ?? output).toInt();
        if (u['input_tokens'] is num) input = (u['input_tokens'] as num).toInt();
      case 'error':
        final err = (e['error'] as Map?) ?? const {};
        final type = err['type'];
        throw LlmException('Anthropic: ${err['message'] ?? 'the stream failed'}', retryable: type == 'overloaded_error' || type == 'api_error');
    }
  }
  if (stop == 'refusal') throw const LlmException('The model declined to read this label.');
  if (stop == 'max_tokens') throw const LlmException('The answer was cut off before it was complete.', retryable: true);
  return (_parseAnswer(answer.toString()), answered, input, output);
}

Future<(Map<String, dynamic>, String, int, int)> _openai(http.Client c, String key, String model, String effort, String system, String text,
    List<LlmImage> images, Map<String, dynamic> schema, String schemaName) async {
  final body = {
    'model': model,
    'instructions': system,
    'reasoning': {'effort': effort},
    'text': {
      'format': {'type': 'json_schema', 'name': schemaName, 'schema': schema, 'strict': true},
    },
    'input': [
      {
        'role': 'user',
        'content': [
          for (final i in images) {'type': 'input_image', 'image_url': 'data:${i.mediaType};base64,${base64Encode(i.bytes)}', 'detail': 'high'},
          {'type': 'input_text', 'text': text},
        ],
      },
    ],
    'store': false,
  };
  final res = await c.post(
    Uri.parse('https://api.openai.com/v1/responses'),
    headers: {'content-type': 'application/json', 'authorization': 'Bearer $key'},
    body: jsonEncode(body),
  );
  final j = _decode(res, LlmProvider.openai);
  if (j['status'] == 'incomplete') {
    final why = (j['incomplete_details'] as Map?)?['reason'];
    throw LlmException('The answer was cut off${why == null ? '' : ' ($why)'}.', retryable: why == 'max_output_tokens');
  }
  final out = StringBuffer();
  for (final item in ((j['output'] as List?) ?? const []).cast<Map>()) {
    if (item['type'] != 'message') continue;
    for (final part in ((item['content'] as List?) ?? const []).cast<Map>()) {
      if (part['type'] == 'refusal') throw const LlmException('The model declined to read this label.');
      if (part['type'] == 'output_text') out.write(part['text']);
    }
  }
  final usage = (j['usage'] as Map?) ?? const {};
  return (
    _parseAnswer(out.toString()),
    (j['model'] as String?) ?? model,
    ((usage['input_tokens'] as num?) ?? 0).toInt(),
    ((usage['output_tokens'] as num?) ?? 0).toInt(),
  );
}

Map<String, dynamic> _decode(http.Response res, LlmProvider provider) {
  Map<String, dynamic>? j;
  try {
    j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {}
  if (res.statusCode >= 200 && res.statusCode < 300 && j != null) return j;
  final err = j?['error'];
  final msg = err is Map ? (err['message'] as String? ?? '$err') : (res.reasonPhrase ?? 'HTTP ${res.statusCode}');
  final code = res.statusCode;
  if (code == 401 || code == 403) throw LlmException('${provider.label} refused the key: $msg', keyProblem: true);
  if (code == 404) throw LlmException('${provider.label} does not offer this model to your key: $msg');
  if (code == 429) throw LlmException('${provider.label} rate limit or credit limit: $msg', retryable: true);
  if (code >= 500 || code == 529) throw LlmException('${provider.label} is busy: $msg', retryable: true);
  throw LlmException('${provider.label}: $msg');
}

Map<String, dynamic> _parseAnswer(String text) {
  final t = text.trim();
  try {
    final v = jsonDecode(t);
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  // A model may wrap the object in a code fence despite the schema.
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
  }
  throw const LlmException('The answer was not the JSON that was asked for.', retryable: true);
}

/// The model ids a key can use, which also proves the key works.
Future<List<String>> listModels(LlmProvider provider, String apiKey, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = switch (provider) {
      LlmProvider.anthropic => await c.get(Uri.parse('https://api.anthropic.com/v1/models?limit=1000'),
          headers: {'x-api-key': apiKey, 'anthropic-version': '2026-10-21'}).timeout(const Duration(seconds: 20)),
      LlmProvider.openai =>
        await c.get(Uri.parse('https://api.openai.com/v1/models'), headers: {'authorization': 'Bearer $apiKey'}).timeout(const Duration(seconds: 20)),
    };
    final j = _decode(res, provider);
    return [for (final m in ((j['data'] as List?) ?? const []).cast<Map>()) m['id'] as String]..sort();
  } on TimeoutException {
    throw const LlmException('No answer from the provider.', retryable: true);
  } on SocketException {
    throw const LlmException('No connection.', retryable: true);
  } finally {
    if (client == null) c.close();
  }
}
