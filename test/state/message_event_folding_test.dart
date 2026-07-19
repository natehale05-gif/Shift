import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/citation.dart';
import 'package:shift_ai/models/message_block.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/models/usage_report.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/state/message_event_folding.dart';

ChatMessage _empty() => ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: '',
      timestamp: DateTime(2026, 7, 19),
      status: MessageStatus.streaming,
    );

ChatMessage _fold(ChatMessage start, List<ChatEvent> events) =>
    events.fold(start, foldMessageEvent);

void main() {
  group('foldMessageEvent', () {
    test('thinking deltas merge into one ThinkingBlock, then text follows',
        () {
      final message = _fold(_empty(), const [
        ThinkingDelta('Reading the'),
        ThinkingDelta(' request.'),
        RoutingDetected(StudioType.codeStudio),
        MessageDelta('Here is'),
        MessageDelta(' the plan.'),
      ]);

      expect(message.studioType, StudioType.codeStudio);
      expect(message.blocks, hasLength(2));
      expect((message.blocks[0] as ThinkingBlock).text,
          'Reading the request.');
      expect((message.blocks[1] as TextBlock).text, 'Here is the plan.');
      expect(message.text, 'Here is the plan.');
    });

    test('text after an interleaved block starts a new TextBlock', () {
      final message = _fold(_empty(), const [
        MessageDelta('Before.'),
        ToolUseStarted(id: 't1', tool: 'web_search', label: 'Searching…'),
        MessageDelta('After.'),
      ]);

      expect(message.blocks, hasLength(3));
      expect((message.blocks[0] as TextBlock).text, 'Before.');
      expect(message.blocks[1], isA<ToolUseBlock>());
      expect((message.blocks[2] as TextBlock).text, 'After.');
      // Flat text still accumulates everything for copy/search.
      expect(message.text, 'Before.After.');
    });

    test('tool finish updates the matching block by id', () {
      final message = _fold(_empty(), const [
        ToolUseStarted(id: 't1', tool: 'web_search', label: 'Searching…'),
        ToolUseFinished(id: 't1', detail: '3 sources'),
      ]);

      final block = message.blocks.single as ToolUseBlock;
      expect(block.status, ToolUseStatus.done);
      expect(block.detail, '3 sources');
    });

    test('deep research progress reuses a single chip and relabels it', () {
      final message = _fold(_empty(), const [
        DeepResearchProgress(stage: 'planning'),
        DeepResearchProgress(stage: 'searching', round: 1, query: 'q1'),
        DeepResearchProgress(stage: 'synthesizing'),
      ]);

      final chips = message.blocks.whereType<ToolUseBlock>().toList();
      expect(chips, hasLength(1));
      expect(chips.single.id, deepResearchToolId);
      expect(chips.single.label, 'Writing the report…');
    });

    test('MessageComplete settles running tools and status', () {
      final message = _fold(_empty(), const [
        ToolUseStarted(id: 't1', tool: 'web_search', label: 'Searching…'),
        MessageComplete(),
      ]);

      expect(message.status, MessageStatus.complete);
      expect(
        (message.blocks.single as ToolUseBlock).status,
        ToolUseStatus.done,
      );
    });

    test('citations, usage, and images attach to the message', () {
      final message = _fold(_empty(), [
        ImageGenerated(pngBytes: Uint8List.fromList([1, 2, 3]), alt: 'art'),
        const CitationsReady(
          [Citation(url: 'https://x.test/a', title: 'A')],
        ),
        const UsageReported(
          UsageReport(inputTokens: 10, outputTokens: 20, model: 'mock'),
        ),
      ]);

      expect((message.blocks.single as ImageBlock).pngBytes, isNotNull);
      expect(message.citations.single.title, 'A');
      expect(message.usage!.outputTokens, 20);
    });

    test('error with no prior content produces readable error text', () {
      final message = _fold(_empty(), const [MessageError('boom')]);
      expect(message.status, MessageStatus.error);
      expect(message.text, contains('boom'));
      expect((message.blocks.single as TextBlock).text, contains('boom'));
    });
  });
}
