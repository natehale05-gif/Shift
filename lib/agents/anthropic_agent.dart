import 'dart:convert';

import '../providers/access.dart';
import '../providers/clients/anthropic_text.dart';
import '../providers/streaming/reachability.dart';
import '../providers/streaming/sse_client.dart';
import '../providers/streaming/status_aware.dart';
import 'tools.dart';

/// One request in a tool-using conversation.
///
/// Separate from [AnthropicText] rather than an option on it, and that is a
/// deliberate line: the chat path is shipped and working, and tool use changes
/// the *shape* of the exchange — many messages, echoed assistant turns, results
/// posted back as user content. Bolting it onto a single-message client would
/// put the risk of this wave inside the one that already answers.
///
/// The wire details it does not share:
///
/// * **`tools` in the body**, and the model then answers with `tool_use`
///   content blocks instead of, or as well as, text.
/// * **Arguments arrive as `input_json_delta`** — a JSON string in fragments,
///   per block. Parsing each fragment fails; they are concatenated and parsed
///   once at the end.
/// * **`stop_reason: 'tool_use'`** is how it says it is waiting for you, and it
///   is the only signal that another round is needed.
/// * The assistant's turn has to be **echoed back verbatim**, tool blocks and
///   all, or the next request has no idea which call the results answer.
class AnthropicAgent {
  static const _host = 'api.anthropic.com';

  final SseClient _sse;
  final Future<Reach> Function() _reach;

  AnthropicAgent({SseClient? sse, Future<Reach> Function()? reach})
      : _sse = sse ?? SseClient(),
        _reach = reach ?? probeReach;

  static Map<String, dynamic> buildBody({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<AgentTool> tools,
    String? system,
    int maxTokens = 16000,
  }) =>
      {
        'model': model,
        'max_tokens': maxTokens,
        if (system != null && system.isNotEmpty) 'system': system,
        'messages': messages,
        'tools': toolSchemas(tools),
        'stream': true,
      };

  /// Sends one round and returns what the model said and asked for.
  ///
  /// [onText] receives prose as it streams, so the surface can show the agent
  /// thinking aloud rather than a spinner between tool calls.
  Future<AgentRound> round({
    required ProviderAccess access,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<AgentTool> tools,
    String? system,
    void Function(String)? onText,
  }) async {
    final target = AnthropicText.target(access);

    final events = statusAware(
      _sse.postJson(
        uri: target.uri,
        headers: target.headers,
        body: jsonEncode(buildBody(
          model: model,
          messages: messages,
          tools: tools,
          system: system,
        )),
      ),
      host: _host,
      reach: _reach,
    );

    return fold(events, onText: onText);
  }

  /// Folds the stream into a round. Static and taking a stream, so every wire
  /// case below can be pinned against recorded frames with no HTTP at all.
  static Future<AgentRound> fold(
    Stream<SseEvent> events, {
    void Function(String)? onText,
  }) async {
    final text = StringBuffer();
    final calls = <int, _PartialCall>{};
    String? stopReason;
    String? failure;
    String? detail;

    await for (final event in events) {
      if (event.data.isEmpty) continue;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      switch (event.event) {
        case 'content_block_start':
          final index = payload['index'] as int? ?? 0;
          final block = payload['content_block'] as Map<String, dynamic>?;
          if (block?['type'] == 'tool_use') {
            calls[index] = _PartialCall(
              id: '${block?['id']}',
              name: '${block?['name']}',
            );
          }

        case 'content_block_delta':
          final index = payload['index'] as int? ?? 0;
          final delta = payload['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              final chunk = delta!['text'] as String? ?? '';
              text.write(chunk);
              onText?.call(chunk);
            case 'input_json_delta':
              // Fragments of a JSON string. Parsing each one throws; they are
              // concatenated and parsed once when the block closes.
              calls[index]?.json.write(delta!['partial_json'] as String? ?? '');
          }

        case 'message_delta':
          stopReason =
              (payload['delta'] as Map<String, dynamic>?)?['stop_reason']
                      as String? ??
                  stopReason;

        case 'error':
          final read = readErrorFrame(payload);
          failure = read.reason;
          detail = read.detail;
      }
    }

    return AgentRound(
      text: text.toString(),
      calls: [
        for (final entry in calls.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
          entry.value.finish(),
      ],
      stopReason: stopReason,
      failure: failure,
      failureDetail: detail,
    );
  }
}

class _PartialCall {
  final String id;
  final String name;
  final StringBuffer json = StringBuffer();

  _PartialCall({required this.id, required this.name});

  ToolCall finish() {
    final raw = json.toString();
    Map<String, dynamic> input;
    try {
      input = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // A model can emit malformed JSON, and a round that throws here would
      // lose the whole turn. An empty argument set reaches the tool, which
      // refuses it and tells the model — which is recoverable.
      input = <String, dynamic>{};
    }
    return ToolCall(id: id, name: name, input: input);
  }
}

/// A tool the model asked to use.
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ToolCall({required this.id, required this.name, required this.input});

  /// The block that has to be echoed back in the assistant's turn, or the
  /// results in the next request answer nothing.
  Map<String, dynamic> get block =>
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input};
}

/// What one round produced.
class AgentRound {
  final String text;
  final List<ToolCall> calls;
  final String? stopReason;
  final String? failure;
  final String? failureDetail;

  const AgentRound({
    this.text = '',
    this.calls = const [],
    this.stopReason,
    this.failure,
    this.failureDetail,
  });

  /// Whether the model is waiting on tool results.
  bool get wantsTools => calls.isNotEmpty;

  /// The assistant turn to append to the conversation.
  Map<String, dynamic> get assistantMessage => {
        'role': 'assistant',
        'content': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          for (final call in calls) call.block,
        ],
      };
}
