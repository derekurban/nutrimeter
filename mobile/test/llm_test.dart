import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nutrimeter/services/llm.dart';

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['ok'],
  'properties': {'ok': {'type': 'boolean'}},
};

Future<LlmResult> _call(LlmProvider p, http.Client c, {String model = 'claude-opus-5-5'}) => callLlm(
      provider: p,
      apiKey: 'k',
      model: model,
      effort: 'high',
      system: 'sys',
      text: 'read it',
      images: const [LlmImage([1, 2, 3], 'image/jpeg')],
      schema: _schema,
      schemaName: 'answer',
      client: c,
    );

void main() {
  test('Anthropic: a streamed answer, with the image, schema, effort and fallback in the request', () async {
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final c = MockClient.streaming((req, body) async {
      sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      headers = req.headers;
      final events = [
        {'type': 'message_start', 'message': {'model': 'claude-opus-5-5', 'usage': {'input_tokens': 1200}}},
        {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'thinking', 'thinking': ''}},
        {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': ''}},
        {'type': 'content_block_start', 'index': 1, 'content_block': {'type': 'text', 'text': ''}},
        {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'text_delta', 'text': '{"ok":'}},
        {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'text_delta', 'text': 'true}'}},
        {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 345}},
        {'type': 'message_stop'},
      ];
      final sse = events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();
      return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
    });
    final r = await _call(LlmProvider.anthropic, c);
    expect(r.json, {'ok': true});
    expect(r.inputTokens, 1200);
    expect(r.outputTokens, 345);
    expect(r.costUsd, closeTo((1200 * 4 + 345 * 20) / 1e6, 1e-12));
    expect(headers['x-api-key'], 'k');
    expect(headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(sent['stream'], true);
    expect(sent['fallbacks'], 'default');
    expect(sent['output_config']['effort'], 'high');
    expect(sent['output_config']['format']['type'], 'json_schema');
    final content = sent['messages'][0]['content'] as List;
    expect(content.first['type'], 'image');
    expect(content.first['source']['data'], base64Encode([1, 2, 3]));
    expect(sent.containsKey('temperature'), isFalse);
  });

  test('Anthropic: a refused key and a refusal read as such', () async {
    final bad = MockClient((_) async => http.Response(jsonEncode({'type': 'error', 'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'}}), 401));
    await expectLater(_call(LlmProvider.anthropic, bad), throwsA(isA<LlmException>().having((e) => e.keyProblem, 'keyProblem', true)));

    final refused = MockClient.streaming((_, _) async => http.StreamedResponse(
        Stream.value(utf8.encode('data: ${jsonEncode({'type': 'message_delta', 'delta': {'stop_reason': 'refusal'}, 'usage': {'output_tokens': 3}})}\n\n')), 200));
    await expectLater(_call(LlmProvider.anthropic, refused), throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('declined'))));
  });

  test('OpenAI: the Responses API with a strict schema and the image as a data URL', () async {
    late Map<String, dynamic> sent;
    final c = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.headers['authorization'], 'Bearer k');
      return http.Response(
          jsonEncode({
            'model': 'gpt-6.1-sol',
            'status': 'completed',
            'output': [
              {'type': 'reasoning', 'summary': []},
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': '{"ok":false}'},
                ],
              },
            ],
            'usage': {'input_tokens': 900, 'output_tokens': 100},
          }),
          200);
    });
    final r = await _call(LlmProvider.openai, c, model: 'gpt-6.1-sol');
    expect(r.json, {'ok': false});
    expect(r.costUsd, closeTo((900 * 2 + 100 * 10) / 1e6, 1e-12));
    expect(sent['text']['format']['strict'], true);
    expect(sent['text']['format']['name'], 'answer');
    expect(sent['reasoning']['effort'], 'high');
    expect((sent['input'][0]['content'] as List).first['image_url'], startsWith('data:image/jpeg;base64,'));
  });

  test('Anthropic: a schema too large to compile is asked again with the schema in the instructions', () async {
    final sent = <Map<String, dynamic>>[];
    final c = MockClient.streaming((req, body) async {
      final j = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      sent.add(j);
      if (sent.length == 1) {
        final err = jsonEncode({
          'type': 'error',
          'error': {'type': 'invalid_request_error', 'message': 'The compiled grammar is too large, which would cause performance issues. Simplify your tool schemas or reduce the number of strict tools.'},
        });
        return http.StreamedResponse(Stream.value(utf8.encode(err)), 400);
      }
      final events = [
        {'type': 'message_start', 'message': {'model': 'claude-haiku-5-5', 'usage': {'input_tokens': 10}}},
        {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': '```json\n{"ok": true}\n```'}},
        {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 5}},
      ];
      return http.StreamedResponse(Stream.value(utf8.encode(events.map((e) => 'data: ${jsonEncode(e)}\n\n').join())), 200);
    });
    final r = await _call(LlmProvider.anthropic, c, model: 'claude-haiku-5-5');
    expect(r.json, {'ok': true});
    expect(sent.length, 2);
    expect(sent[0]['output_config']['format'], isNotNull);
    expect((sent[1]['output_config'] as Map).containsKey('format'), isFalse);
    expect(sent[1]['system'], contains('"additionalProperties":false'));
  });
}
