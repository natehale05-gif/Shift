import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/providers/anthropic_client.dart';
import 'package:shift_ai/services/providers/anthropic_stream_accumulator.dart';
import 'package:shift_ai/services/streaming/sse_client.dart';

/// First round of a web-search turn that pauses mid-loop.
const _pausedRound = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_a","usage":{"input_tokens":30}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtool_1","name":"web_search","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":\\"ai"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":" chips\\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"pause_turn"},"usage":{"output_tokens":12}}

event: message_stop
data: {"type":"message_stop"}
''';

/// Second round: results come back, cited prose streams, turn ends.
const _resumedRound = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_b","usage":{"input_tokens":55}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtool_1","content":[{"type":"web_search_result","url":"https://ex.test/1","title":"One"},{"type":"web_search_result","url":"https://ex.test/2","title":"Two"}]}}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Chips are advancing."}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://ex.test/1","title":"One","cited_text":"chips advanced"}}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":40}}

event: message_stop
data: {"type":"message_stop"}
''';

const _codeExecRound = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_c","usage":{"input_tokens":20}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtool_9","name":"code_execution","input":{}}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"bash_code_execution_tool_result","tool_use_id":"srvtool_9","content":{"type":"bash_code_execution_result","stdout":"832040\\n","stderr":"","return_code":0}}}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"fib(30) = 832040"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}

event: message_stop
data: {"type":"message_stop"}
''';

Stream<SseEvent> _events(String fixture) =>
    parseSseLines(Stream.fromIterable(const LineSplitter().convert(fixture)));

Future<(List<ChatEvent>, AnthropicStreamAccumulator)> _accumulate(
    String fixture) async {
  final accumulator = AnthropicStreamAccumulator();
  final chatEvents = <ChatEvent>[];
  await for (final event in _events(fixture)) {
    chatEvents.addAll(accumulator.onSseEvent(event));
  }
  return (chatEvents, accumulator);
}

/// Fake SSE transport returning scripted rounds in order and recording the
/// request bodies (to assert the pause_turn continuation shape).
class _ScriptedSse implements SseClient {
  final List<String> rounds;
  final List<Map<String, dynamic>> requests = [];
  int _round = 0;

  _ScriptedSse(this.rounds);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    requests.add(jsonDecode(body) as Map<String, dynamic>);
    return _events(rounds[_round++]);
  }
}

Conversation _conversation() => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('accumulator maps server tool start/finish and rebuilds tool input',
      () async {
    final (events, accumulator) = await _accumulate(_pausedRound);

    final started = events.whereType<ToolUseStarted>().single;
    expect(started.tool, 'web_search');
    expect(started.label, 'Searching the web…');
    expect(accumulator.stopReason, 'pause_turn');
    // Streamed partial_json folded back into the block for resumption.
    expect(accumulator.contentBlocks.single['input'],
        {'query': 'ai chips'});
  });

  test('accumulator maps search results, citations, and code exec output',
      () async {
    final (events, accumulator) = await _accumulate(_resumedRound);
    final finished = events.whereType<ToolUseFinished>().single;
    expect(finished.id, 'srvtool_1');
    expect(finished.detail, '2 results');
    expect(accumulator.citations.single.title, 'One');

    final (codeEvents, _) = await _accumulate(_codeExecRound);
    final codeFinished = codeEvents.whereType<ToolUseFinished>().single;
    expect(codeFinished.detail, '832040');
    expect(codeFinished.failed, isFalse);
  });

  test(
      'streamChat resumes pause_turn with accumulated assistant blocks and '
      'merges usage + citations across rounds', () async {
    final sse = _ScriptedSse([_pausedRound, _resumedRound]);
    final client = AnthropicClient(sseClient: sse);

    final events = await client.streamChat(
      apiKey: 'sk-test',
      conversation: _conversation(),
      userInput: 'latest ai chip news',
      model: 'claude-opus-4-8',
      tools: const [
        {'type': 'web_search_20260209', 'name': 'web_search'},
      ],
    ).toList();

    // Two requests were made; the second carries the paused assistant turn.
    expect(sse.requests, hasLength(2));
    final resumedMessages = sse.requests[1]['messages'] as List;
    final lastMessage = resumedMessages.last as Map;
    expect(lastMessage['role'], 'assistant');
    final resumedBlocks = lastMessage['content'] as List;
    expect((resumedBlocks.single as Map)['type'], 'server_tool_use');

    // Events from both rounds flowed into one stream.
    expect(events.whereType<ToolUseStarted>(), hasLength(1));
    expect(events.whereType<ToolUseFinished>(), hasLength(1));
    expect(
      events.whereType<MessageDelta>().map((e) => e.chunk).join(),
      'Chips are advancing.',
    );
    final citations = events.whereType<CitationsReady>().single.citations;
    expect(citations.single.url, 'https://ex.test/1');
    final usage = events.whereType<UsageReported>().single.usage;
    expect(usage.inputTokens, 30 + 55);
    expect(usage.outputTokens, 12 + 40);
    expect(events.last, isA<MessageComplete>());
  });
}
