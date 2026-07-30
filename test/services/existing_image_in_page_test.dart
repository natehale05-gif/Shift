import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/anthropic_api_config.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/prompt_assembler.dart';

/// Not real PNG bytes — nothing decodes them here, they only have to come out
/// the other end base64-encoded into the page.
final _flowerBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

/// What the model writes back. It leaves the placeholder it was told to leave.
const _pageWithPlaceholder = '<!DOCTYPE html>\n'
    '<html>\n'
    '<body>\n'
    '<h1>Blooms</h1>\n'
    '<img src="{{shift:image}}" alt="pink flower">\n'
    '</body>\n'
    '</html>';

/// What a model that ignores the instruction writes.
const _pageWithoutPlaceholder = '<!DOCTYPE html>\n'
    '<html>\n'
    '<body>\n'
    '<h1>Blooms</h1>\n'
    '</body>\n'
    '</html>';

class _ForcedRouter extends ModelRouter {
  /// The classifier sees one sentence with no conversation around it, and
  /// "put this image in the website" reads to it like an image request — the
  /// route must not be what decides this, so pin the wrong answer here.
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.imageGen;
}

class _FakeAnthropicClient extends AnthropicClient {
  final String page;
  final String lang;
  String? seenSystemPrompt;
  int callCount = 0;

  _FakeAnthropicClient(this.page, {this.lang = 'html'});

  @override
  Stream<ChatEvent> streamChat({
    required String apiKey,
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    List<Map<String, dynamic>> tools = const [],
    bool extendedThinking = true,
    int maxContinuations = 5,
    int maxTokens = AnthropicApiConfig.defaultMaxTokens,
  }) async* {
    callCount++;
    seenSystemPrompt = systemPrompt;
    yield const MessageDelta('Here it is.\n\n');
    yield MessageDelta('```$lang\n$page\n```');
    yield const MessageComplete();
  }
}

Conversation _afterGeneratingAnImage(
  String userInput, {
  List<Artifact> artifacts = const [],
}) =>
    Conversation(
      id: 'c1',
      title: 'Image of a pink flower',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      artifacts: artifacts,
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'image of a pink flower',
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: 'Here it is.',
          blocks: [
            const TextBlock('Here it is.'),
            ImageBlock(alt: 'photorealistic pink flower', pngBytes: _flowerBytes),
          ],
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'u2',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'a2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 30),
        ),
      ],
    );

Future<(List<ChatEvent>, _FakeAnthropicClient)> _runLive(
  String prompt, {
  String page = _pageWithPlaceholder,
  String lang = 'html',
  List<Artifact> artifacts = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  final client = _FakeAnthropicClient(page, lang: lang);
  final service = RealChatService(
    keys: keys,
    anthropicClient: client,
    router: _ForcedRouter(),
  );
  final events = await service
      .sendMessage(
        conversation: _afterGeneratingAnImage(prompt, artifacts: artifacts),
        userInput: prompt,
      )
      .toList();
  return (events, client);
}

Future<List<ChatEvent>> _runMock(
  String prompt, {
  List<Artifact> artifacts = const [],
}) =>
    MockChatService()
        .sendMessage(
          conversation: _afterGeneratingAnImage(prompt, artifacts: artifacts),
          userInput: prompt,
        )
        .toList();

Artifact _existingPage() => Artifact(
      id: 'page-1',
      conversationId: 'c1',
      title: 'Blooms',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
          content: '<html><body><h1>Blooms</h1></body></html>',
          createdAt: DateTime(2026, 7, 30),
        ),
      ],
    );

/// The image bytes, base64-encoded the way a data URI carries them.
const _flowerInPage = 'data:image/png;base64,iVBORw0KGgo=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live', () {
    test('the image already in the chat ends up in the page', () async {
      // The reported bug: this produced a page referencing "pink-flower.jpg"
      // and a note asking the user to save a file next to it. There is no
      // "next to", and the user has no such file.
      final (events, client) = await _runLive('now put this image in the website');

      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.kind, ArtifactKind.html);
      expect(created.artifact.latest.content, contains(_flowerInPage));
      expect(created.artifact.latest.content, isNot(contains('{{shift:image}}')));
      // One version, not two — the page was never shown without the image.
      expect(created.artifact.versions, hasLength(1));
      expect(client.callCount, 1);
    });

    test('"put it in a website selling pink flowers" works too', () async {
      // Same request, said with a pronoun — which is how people actually say
      // it. This phrasing shipped broken once already.
      final (events, client) =
          await _runLive('put it in a website selling pink flowers');

      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.latest.content, contains(_flowerInPage));
      expect(client.seenSystemPrompt, contains(existingImageInstruction));
    });

    test('a jsx component gets the image too', () async {
      // "Put it in a jsx website" produces a *code* artifact. Substitution used
      // to be gated on html, so the model was asked to leave a placeholder that
      // nothing ever replaced — shipping a component with a literal
      // {{shift:image}} in its src.
      final (events, _) = await _runLive('now put it in a jsx website',
          lang: 'jsx',
          page: 'import React from "react";\n'
              '\n'
              'export default function App() {\n'
              '  return (\n'
              '    <main>\n'
              '      <h1>Blooms</h1>\n'
              '      <img src="{{shift:image}}" alt="flower" />\n'
              '    </main>\n'
              '  );\n'
              '}');

      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.latest.content, contains(_flowerInPage));
      expect(created.artifact.latest.content, isNot(contains('{{shift:image}}')));
    });

    test('a model that ignores the placeholder still gets the image', () async {
      final (events, _) = await _runLive('now put this image in the website',
          page: _pageWithoutPlaceholder);

      expect(events.whereType<ArtifactCreated>().single.artifact.latest.content,
          contains(_flowerInPage));
    });

    test('the model is told the image exists and how to place it', () async {
      final (_, client) = await _runLive('now put this image in the website');

      expect(client.seenSystemPrompt, contains(existingImageInstruction));
    });

    test('an ordinary page build says nothing about an existing image',
        () async {
      final (_, client) = await _runLive('build me a landing page for a bakery');

      expect(client.seenSystemPrompt, isNot(contains(existingImageInstruction)));
    });

    test('with a page already there, it gains a version — no second page',
        () async {
      final (events, client) = await _runLive('now put this image in the website',
          artifacts: [_existingPage()]);

      expect(events.whereType<ArtifactCreated>(), isEmpty);
      final updated = events.whereType<ArtifactUpdated>().single;
      expect(updated.artifact.id, 'page-1');
      expect(updated.artifact.versions, hasLength(2));
      expect(updated.artifact.latest.content, contains(_flowerInPage));
      // No provider call at all: the picture exists, and the page exists.
      expect(client.callCount, 0);
    });
  });

  group('demo mode', () {
    test('agrees — the image goes on the page it just built', () async {
      final events = await _runMock('now put this image in the website');

      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.kind, ArtifactKind.html);
      expect(created.artifact.latest.content, contains(_flowerInPage));
    });

    test('agrees — an existing page gains a version carrying the image',
        () async {
      final events = await _runMock('now put this image in the website',
          artifacts: [_existingPage()]);

      final updated = events.whereType<ArtifactUpdated>().single;
      expect(updated.artifact.id, 'page-1');
      expect(updated.artifact.latest.content, contains(_flowerInPage));
    });
  });
}
