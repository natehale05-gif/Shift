import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/features/artifacts/mermaid_service.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

Conversation _empty() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 21),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MermaidService.buildHtml wraps the source with the bundled runtime',
      () async {
    final html = await MermaidService.buildHtml('flowchart TD; A-->B',
        dark: true);
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('mermaid.render'));
    expect(html, contains('flowchart TD; A-->B')); // source injected verbatim
    expect(html, contains('mermaid.initialize'));
    expect(html, contains("theme: 'dark'"));
    // The bundled runtime is inlined (not a CDN reference).
    expect(html.contains('cdn.jsdelivr'), isFalse);
    expect(html.length, greaterThan(100000)); // the ~3MB script is embedded
  });

  test('a diagram request streams a live ```mermaid fence in demo mode',
      () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _empty(),
          userInput: 'draw a flowchart of how a request is handled',
        )
        .toList();
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, contains('```mermaid'));
    expect(text, contains('flowchart'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
