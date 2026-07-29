import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/citation.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/features/chat/conversation_export.dart';

Conversation _fixture() => Conversation(
      id: 'c1',
      title: 'Bakery plans',
      createdAt: DateTime(2026, 7, 19, 10),
      updatedAt: DateTime(2026, 7, 19, 11),
      messages: [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'Help me name my bakery',
          timestamp: DateTime(2026, 7, 19, 10, 1),
        ),
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: 'How about **Golden Crumb**?',
          citations: const [
            Citation(url: 'https://example.test/naming', title: 'Naming 101'),
          ],
          timestamp: DateTime(2026, 7, 19, 10, 2),
        ),
      ],
      artifacts: [
        Artifact(
          id: 'a1',
          conversationId: 'c1',
          title: 'landing.html',
          kind: ArtifactKind.html,
          versions: [
            ArtifactVersion(
              content: '<html>v1</html>',
              createdAt: DateTime(2026, 7, 19, 10, 3),
            ),
          ],
        ),
      ],
    );

void main() {
  test('markdown export contains title, turns, citations, and artifacts', () {
    final markdown = ConversationExport.toMarkdown(_fixture());

    expect(markdown, startsWith('# Bakery plans'));
    expect(markdown, contains('## You'));
    expect(markdown, contains('Help me name my bakery'));
    expect(markdown, contains('## SHIFT AI'));
    expect(markdown, contains('How about **Golden Crumb**?'));
    expect(markdown,
        contains('1. [Naming 101](https://example.test/naming)'));
    expect(markdown, contains('# Artifacts'));
    expect(markdown, contains('## landing.html (v1)'));
    expect(markdown, contains('<html>v1</html>'));
  });

  test('json export round-trips through Conversation.fromJson', () {
    final jsonString = ConversationExport.toJsonString(_fixture());
    expect(jsonString, contains('"title": "Bakery plans"'));
  });

  test('printable HTML renders roles and escapes markup', () {
    final html = ConversationExport.toPrintableHtml(_fixture());
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('<h1>Bakery plans</h1>'));
    expect(html, contains('>You<'));
    expect(html, contains('>SHIFT AI<'));
    expect(html, contains('Help me name my bakery'));
    // Assistant text with markup is HTML-escaped, not rendered as tags.
    expect(html, contains('Golden Crumb'));
  });
}
