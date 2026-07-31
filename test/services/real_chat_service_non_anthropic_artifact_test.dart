import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/gemini_api_config.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/providers/clients/openai_compatible_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// A page whose headline reflects the request, the way a real model's would.
///
/// The fixture used to return one canned page for every prompt. That was
/// invisible while titles came from the request, and became visible the moment
/// they came from the page — two different requests producing byte-identical
/// pages is not something a model does.
String _pageFor(String prompt) {
  final subject = prompt.split(' ').last;
  return '<!DOCTYPE html>\n<html>\n<head><title>The $subject</title></head>\n'
      '<body>\n<h1>The $subject</h1>\n'
      '<p>Not written by Claude.</p>\n</body>\n</html>';
}

class _ForcedRouter extends ModelRouter {
  final ChatRoute _route;
  _ForcedRouter([this._route = ChatRoute.code]);

  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      _route;
}

/// Records whether it was actually called, so a test can tell "Gemini built
/// the page" apart from "the backend quietly fell back to the mock".
class _FakeGeminiClient extends GeminiClient {
  int callCount = 0;

  /// What the model replies. Defaults to a page, but a plain question has to
  /// be answered with prose: a fake that returns `<!DOCTYPE html>` no matter
  /// what is asked cannot tell "the route gate held" apart from "the reply
  /// contained nothing worth extracting".
  final String reply;
  _FakeGeminiClient({this.reply = ''});

  @override
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required Conversation conversation,
    required String userInput,
    String model = GeminiApiConfig.flashModel,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    bool grounding = false,
  }) async* {
    callCount++;
    yield MessageDelta(reply.isEmpty
        ? 'Sure:\n\n```html\n${_pageFor(userInput)}\n```'
        : reply);
    yield const MessageComplete();
  }
}

class _FakeOpenAiClient extends OpenAiCompatibleClient {
  int callCount = 0;

  final String reply;
  _FakeOpenAiClient({this.reply = ''});

  @override
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required String baseUrl,
    required String model,
    required Conversation conversation,
    required String userInput,
    String displayName = '',
    List<Attachment> attachments = const [],
    String? systemPrompt,
    Map<String, String> extraHeaders = const {},
  }) async* {
    callCount++;
    yield MessageDelta(reply.isEmpty
        ? 'Sure:\n\n```html\n${_pageFor(userInput)}\n```'
        : reply);
    yield const MessageComplete();
  }
}

/// How a model actually answers a question that is not a build request.
const _proseReply = 'The capital of France is Paris.';

Artifact _existingPage() => Artifact(
      id: 'a1',
      conversationId: 'c1',
      title: 'Northbound landing page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
          content: '<html><body><h1>Old</h1></body></html>',
          createdAt: DateTime(2026, 7, 20),
        ),
      ],
    );

Conversation _conversation(String userInput, List<Artifact> artifacts) =>
    Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      artifacts: artifacts,
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1m',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

Future<ApiKeysStore> _keysFor(String provider, String value) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setKey(provider, value);
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gemini-only user', () {
    Future<(List<ChatEvent>, _FakeGeminiClient)> run(
      String prompt, {
      List<Artifact> artifacts = const [],
      ChatRoute route = ChatRoute.code,
      String? reply,
    }) async {
      final keys = await _keysFor('gemini', 'test-gemini-key');
      final gemini = reply == null
          ? _FakeGeminiClient()
          : _FakeGeminiClient(reply: reply);
      final service = RealChatService(
        keys: keys,
        geminiClient: gemini,
        router: _ForcedRouter(route),
      );
      final events = await service
          .sendMessage(
            conversation: _conversation(prompt, artifacts),
            userInput: prompt,
          )
          .toList();
      return (events, gemini);
    }

    test('builds a real artifact instead of falling back to the mock',
        () async {
      // Gemini did not advertise the code capability, so chooseProvider
      // returned null and the backend served the simulated demo page while the
      // user's key went untouched.
      final (events, gemini) = await run('build me a landing page for my bakery');

      expect(gemini.callCount, 1, reason: 'Gemini must actually be called');
      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.kind, ArtifactKind.html);
      expect(created.artifact.latest.content, contains('Not written by Claude'));
    });

    test('two prompts get two titles, not "Generated page" twice', () async {
      // Every live artifact used to carry the same constant title, which is
      // also the download filename -- so a second download collided with the
      // first and the sidebar showed a column of identical names.
      final (first, _) = await run('build me a landing page for my bakery');
      final (second, _) = await run('build me a landing page for a law firm');

      final a = first.whereType<ArtifactCreated>().single.artifact.title;
      final b = second.whereType<ArtifactCreated>().single.artifact.title;

      expect(a, isNot(b));
      expect(a, isNot('Generated page'));
      expect(a, contains('bakery'));
    });

    test('honours the create-vs-revise decision', () async {
      final (events, _) = await run(
        'change the code so the heading is bigger',
        artifacts: [_existingPage()],
      );

      expect(events.whereType<ArtifactCreated>(), isEmpty);
      final updated = events.whereType<ArtifactUpdated>().single;
      expect(updated.artifact.id, 'a1');
      expect(updated.artifact.versions, hasLength(2));
    });

    test('page contributors weave into a Gemini-built page', () async {
      // pageContributors only ever reached the Claude path, so a multi-studio
      // build on any other provider produced a bare page.
      final (events, gemini) =
          await run('build me a bakery website with a soundtrack');

      expect(gemini.callCount, 1);
      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.latest.content, contains('<audio controls'));
      expect(created.artifact.latest.content, contains('Soundtrack'));
      // Gemini's own markup survives the splice.
      expect(created.artifact.latest.content, contains('Not written by Claude'));
    });

    test('a non-code route still produces no artifact', () async {
      final (events, gemini) = await run('what is the capital of France',
          route: ChatRoute.chat, reply: _proseReply);

      expect(gemini.callCount, 1);
      expect(events.whereType<ArtifactCreated>(), isEmpty);
      expect(events.whereType<ArtifactUpdated>(), isEmpty);
    });

    test('a whole page becomes an artifact even off the code route', () async {
      // Routing is a classification and it is sometimes wrong -- most often
      // on a follow-up like "give it to me as an artifact", which the router
      // sees with no conversation around it. When that happens the old gate
      // dropped a finished page into a chat bubble, where it could not be
      // previewed, downloaded or revised. A complete document is a
      // deliverable regardless of what the router decided.
      final (events, _) = await run('give it to me as an artifact',
          route: ChatRoute.chat);

      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.kind, ArtifactKind.html);
      expect(created.artifact.latest.content, contains('<!DOCTYPE html>'));
    });

    test('a code fragment in a chat answer stays in the chat', () async {
      // The other half of the same decision: a few tags quoted to explain
      // something must not become an artifact.
      final (events, _) = await run('how do I centre a div',
          route: ChatRoute.chat,
          reply: 'Use flexbox:\n\n```html\n<div class="row">\n'
              '  <span>a</span>\n  <span>b</span>\n</div>\n```\n'
              'Then add display:flex.');

      expect(events.whereType<ArtifactCreated>(), isEmpty);
    });
  });

  group('pinned model', () {
    test('a pinned model still produces an artifact for a page request',
        () async {
      // A pin says which model answers, not what kind of answer it is. It used
      // to force ChatRoute.chat, so "pin a model, ask for a landing page"
      // dropped the deliverable and left a fenced block in the chat.
      final keys = await _keysFor('openai', 'test-openai-key');
      final openAi = _FakeOpenAiClient();
      final service = RealChatService(
        keys: keys,
        openAiClient: openAi,
        router: _ForcedRouter(),
      );
      final events = await service
          .sendMessage(
            conversation: _conversation('build me a landing page', const []),
            userInput: 'build me a landing page',
            options: const ChatOptions(modelPin: 'gpt-4o'),
          )
          .toList();

      expect(openAi.callCount, 1);
      expect(events.whereType<ArtifactCreated>().single.artifact.kind,
          ArtifactKind.html);
    });

    test('a pinned model on a plain question still produces no artifact',
        () async {
      // The pin must not start routing ordinary chat into studios.
      final keys = await _keysFor('openai', 'test-openai-key');
      final openAi = _FakeOpenAiClient(reply: _proseReply);
      final service = RealChatService(
        keys: keys,
        openAiClient: openAi,
        router: _ForcedRouter(),
      );
      final events = await service
          .sendMessage(
            conversation: _conversation('what is the capital of France', const []),
            userInput: 'what is the capital of France',
            options: const ChatOptions(modelPin: 'gpt-4o'),
          )
          .toList();

      expect(openAi.callCount, 1);
      expect(events.whereType<ArtifactCreated>(), isEmpty);
    });
  });

  group('OpenAI-compatible user', () {
    test('a code-routed reply becomes an artifact', () async {
      // These providers already advertised code, so they were selected -- but
      // their reply was streamed straight through with no artifact extraction,
      // leaving a code fence in the chat and an empty side panel.
      final keys = await _keysFor('openai', 'test-openai-key');
      final openAi = _FakeOpenAiClient();
      final service = RealChatService(
        keys: keys,
        openAiClient: openAi,
        router: _ForcedRouter(),
      );
      final events = await service
          .sendMessage(
            conversation: _conversation('build me a landing page', const []),
            userInput: 'build me a landing page',
          )
          .toList();

      expect(openAi.callCount, 1);
      final created = events.whereType<ArtifactCreated>().single;
      expect(created.artifact.kind, ArtifactKind.html);
    });
  });
}
