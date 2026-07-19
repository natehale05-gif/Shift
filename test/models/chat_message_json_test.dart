import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/message_block.dart';

void main() {
  test('v1 message JSON (no blocks) migrates to a single TextBlock', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'conversationId': 'c1',
      'role': 'assistant',
      'studioType': null,
      'text': 'Hello from v1.',
      'studioResult': null,
      'timestamp': '2026-07-19T12:00:00.000',
      'status': 'complete',
    });

    expect(message.blocks, hasLength(1));
    expect((message.blocks.single as TextBlock).text, 'Hello from v1.');
    expect(message.citations, isEmpty);
    expect(message.attachments, isEmpty);
  });

  test('v2 message round-trips blocks, citations, and usage', () {
    final original = ChatMessage(
      id: 'm2',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: 'Answer.',
      blocks: const [
        ThinkingBlock('Considering.'),
        ToolUseBlock(
          id: 't1',
          tool: 'web_search',
          label: 'Searched the web',
          status: ToolUseStatus.done,
          detail: '3 sources',
        ),
        TextBlock('Answer.'),
        ArtifactRefBlock(
          artifactId: 'a1',
          title: 'page.html',
          kind: ArtifactKind.html,
          versionIndex: 0,
        ),
      ],
      timestamp: DateTime(2026, 7, 19, 12),
    );

    final restored = ChatMessage.fromJson(original.toJson());

    expect(restored.blocks, hasLength(4));
    expect(restored.blocks[0], isA<ThinkingBlock>());
    final tool = restored.blocks[1] as ToolUseBlock;
    expect(tool.detail, '3 sources');
    expect(tool.status, ToolUseStatus.done);
    final ref = restored.blocks[3] as ArtifactRefBlock;
    expect(ref.kind, ArtifactKind.html);
    expect(ref.versionIndex, 0);
  });

  test('image block bytes are dropped on save (localStorage quota guard)',
      () {
    final original = ChatMessage(
      id: 'm3',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: '',
      blocks: [
        ImageBlock(alt: 'art', pngBytes: Uint8List.fromList([9, 9, 9])),
      ],
      timestamp: DateTime(2026, 7, 19, 12),
    );

    final restored = ChatMessage.fromJson(original.toJson());
    final image = restored.blocks.single as ImageBlock;
    expect(image.pngBytes, isNull);
    expect(image.alt, 'art');
  });

  test('conversation round-trips artifacts and starred flag', () {
    final conversation = Conversation(
      id: 'c1',
      title: 'Landing page',
      createdAt: DateTime(2026, 7, 19, 11),
      updatedAt: DateTime(2026, 7, 19, 12),
      starred: true,
      artifacts: [
        Artifact(
          id: 'a1',
          conversationId: 'c1',
          title: 'page.html',
          kind: ArtifactKind.html,
          versions: [
            ArtifactVersion(
              content: '<html></html>',
              createdAt: DateTime(2026, 7, 19, 12),
            ),
            ArtifactVersion(
              content: '<html>v2</html>',
              createdAt: DateTime(2026, 7, 19, 12, 5),
            ),
          ],
        ),
      ],
    );

    final restored = Conversation.fromJson(conversation.toJson());
    expect(restored.starred, isTrue);
    expect(restored.artifacts.single.versions, hasLength(2));
    expect(restored.artifacts.single.latest.content, '<html>v2</html>');
    expect(restored.artifactById('a1'), isNotNull);
    expect(restored.artifactById('missing'), isNull);
  });

  test('v1 conversation JSON without starred/artifacts still loads', () {
    final restored = Conversation.fromJson({
      'id': 'c1',
      'title': 'Old chat',
      'createdAt': '2026-07-19T11:00:00.000',
      'updatedAt': '2026-07-19T12:00:00.000',
      'messages': <dynamic>[],
    });
    expect(restored.starred, isFalse);
    expect(restored.artifacts, isEmpty);
  });
}
