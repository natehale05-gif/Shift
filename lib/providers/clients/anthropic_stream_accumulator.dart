import 'dart:convert';

import '../../data/models/citation.dart';
import '../../turn/chat_service.dart';
import '../streaming/sse_client.dart';
import 'anthropic_tools.dart';

/// Consumes one streamed Messages API response, translating SSE events into
/// [ChatEvent]s while reconstructing the raw assistant `content` blocks —
/// needed verbatim to resume a `pause_turn` continuation. Pure Dart,
/// fixture-tested.
class AnthropicStreamAccumulator {
  final List<Map<String, dynamic>> contentBlocks = [];
  final List<Citation> citations = [];
  final StringBuffer _partialJson = StringBuffer();

  String? stopReason;
  int inputTokens = 0;
  int outputTokens = 0;

  /// Translates one SSE event; returns the ChatEvents to emit for it.
  List<ChatEvent> onSseEvent(SseEvent event) {
    if (event.data.isEmpty) return const [];
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(event.data) as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }

    switch (event.event) {
      case 'message_start':
        final usage =
            (payload['message'] as Map<String, dynamic>?)?['usage'];
        if (usage is Map) {
          inputTokens += usage['input_tokens'] as int? ?? 0;
        }
        return const [];

      case 'content_block_start':
        final block = payload['content_block'] as Map<String, dynamic>?;
        if (block == null) return const [];
        contentBlocks.add(Map<String, dynamic>.from(block));
        _partialJson.clear();
        return switch (block['type'] as String?) {
          'server_tool_use' => [
              ToolUseStarted(
                id: block['id'] as String? ?? 'tool',
                tool: block['name'] as String? ?? 'tool',
                label:
                    AnthropicTools.labelFor(block['name'] as String? ?? ''),
              ),
            ],
          'web_search_tool_result' => [
              ToolUseFinished(
                id: block['tool_use_id'] as String? ?? 'tool',
                detail: _webSearchResultDetail(block),
              ),
            ],
          'bash_code_execution_tool_result' ||
          'code_execution_tool_result' =>
            [
              ToolUseFinished(
                id: block['tool_use_id'] as String? ?? 'tool',
                detail: _codeExecutionDetail(block),
                failed: _codeExecutionFailed(block),
              ),
            ],
          _ => const [],
        };

      case 'content_block_delta':
        final delta = payload['delta'] as Map<String, dynamic>?;
        final block = contentBlocks.isNotEmpty ? contentBlocks.last : null;
        switch (delta?['type']) {
          case 'text_delta':
            final text = delta!['text'] as String? ?? '';
            if (block != null) {
              block['text'] = (block['text'] as String? ?? '') + text;
            }
            return [MessageDelta(text)];
          case 'thinking_delta':
            final thinking = delta!['thinking'] as String? ?? '';
            if (block != null) {
              block['thinking'] =
                  (block['thinking'] as String? ?? '') + thinking;
            }
            return [ThinkingDelta(thinking)];
          case 'signature_delta':
            if (block != null) {
              block['signature'] = (block['signature'] as String? ?? '') +
                  (delta!['signature'] as String? ?? '');
            }
            return const [];
          case 'input_json_delta':
            _partialJson.write(delta!['partial_json'] as String? ?? '');
            return const [];
          case 'citations_delta':
            final citation = delta!['citation'] as Map<String, dynamic>?;
            if (citation != null) {
              if (block != null) {
                ((block['citations'] ??= <dynamic>[]) as List).add(citation);
              }
              final url = citation['url'] as String?;
              if (url != null &&
                  !citations.any((c) => c.url == url)) {
                citations.add(Citation(
                  url: url,
                  title: citation['title'] as String? ?? url,
                  citedText: citation['cited_text'] as String?,
                ));
              }
            }
            return const [];
        }
        return const [];

      case 'content_block_stop':
        // Server tool inputs stream as partial JSON; fold the finished
        // buffer back into the block so continuations carry valid input.
        if (_partialJson.isNotEmpty && contentBlocks.isNotEmpty) {
          try {
            contentBlocks.last['input'] =
                jsonDecode(_partialJson.toString());
          } catch (_) {
            // Leave whatever input the start block carried.
          }
          _partialJson.clear();
        }
        return const [];

      case 'message_delta':
        final delta = payload['delta'] as Map<String, dynamic>?;
        stopReason = delta?['stop_reason'] as String? ?? stopReason;
        final usage = payload['usage'] as Map<String, dynamic>?;
        if (usage != null) {
          outputTokens += usage['output_tokens'] as int? ?? 0;
        }
        return const [];

      case 'error':
        final error = payload['error'] as Map<String, dynamic>?;
        return [
          MessageError(error?['message'] as String? ?? 'Unknown API error'),
        ];
    }
    return const [];
  }

  static String _webSearchResultDetail(Map<String, dynamic> block) {
    final content = block['content'];
    if (content is List) return '${content.length} results';
    return 'done';
  }

  static String? _codeExecutionDetail(Map<String, dynamic> block) {
    final content = block['content'];
    if (content is! Map) return null;
    final stdout = content['stdout'] as String? ?? '';
    final stderr = content['stderr'] as String? ?? '';
    final output = stdout.isNotEmpty ? stdout : stderr;
    if (output.isEmpty) return null;
    final trimmed = output.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }

  static bool _codeExecutionFailed(Map<String, dynamic> block) {
    final content = block['content'];
    return content is Map && (content['return_code'] as int? ?? 0) != 0;
  }
}
