import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/attachment.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';

/// Records how the turn was authorised, and answers with a plain reply so the
/// turn completes.
class _RecordingAnthropic extends AnthropicClient {
  ProviderAccess? seen;
  int callCount = 0;

  @override
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    List<Map<String, dynamic>> tools = const [],
    bool extendedThinking = true,
    int maxContinuations = 5,
    int maxTokens = 16000,
  }) async* {
    seen = access;
    callCount++;
    yield const MessageDelta('Answered.');
    yield const MessageComplete();
  }
}

RealChatService _service({
  required ApiKeysStore keys,
  required _RecordingAnthropic client,
  Set<String> covered = const {},
  ProviderAccess? managed,
}) =>
    RealChatService(
      keys: keys,
      anthropicClient: client,
      managedProviders: () => covered,
      managedAccess: (provider) async =>
          covered.contains(provider) ? managed : null,
    );

Future<ApiKeysStore> _keys({String? anthropic}) async {
  SharedPreferences.setMockInitialValues({});
  final store = ApiKeysStore(persistence: PersistenceService());
  await store.load();
  if (anthropic != null) await store.setKey('anthropic', anthropic);
  return store;
}

final _managed = ManagedAccess(
  base: Uri.parse('https://p.test/functions/v1/provider-proxy/anthropic'),
  headers: const {'Authorization': 'Bearer session-token'},
);

const _prompt = 'Write me a short poem about rain.';

Conversation _conversation() => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 31),
      updatedAt: DateTime(2026, 7, 31),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: _prompt,
          timestamp: DateTime(2026, 7, 31),
        ),
      ],
    );

Future<List<ChatEvent>> _run(RealChatService service) =>
    service.sendMessage(conversation: _conversation(), userInput: _prompt)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a member with a plan and no key of their own reaches a real provider',
      () async {
    // The regression the whole wave turns on. `chooseProvider` asks whether a
    // provider is usable; before this it asked only about locally stored keys,
    // so a paying member with nothing in Settings routed to the mock and their
    // membership bought nothing.
    final client = _RecordingAnthropic();
    final service = _service(
      keys: await _keys(),
      client: client,
      covered: const {'anthropic'},
      managed: _managed,
    );

    await _run(service);

    expect(client.callCount, 1, reason: 'the turn fell back to the mock');
    expect(client.seen, isA<ManagedAccess>());
  });

  test('the membership pays even when the member also has their own key',
      () async {
    // They pay monthly for the plan, so the plan is what gets spent.
    final client = _RecordingAnthropic();
    final service = _service(
      keys: await _keys(anthropic: 'sk-their-own-key'),
      client: client,
      covered: const {'anthropic'},
      managed: _managed,
    );

    await _run(service);

    expect(client.seen, isA<ManagedAccess>());
  });

  test('their own key takes over when the plan cannot pay', () async {
    // `AccountStore.managedAccess` returns null once the subscription lapses
    // or the ceiling is spent, so running out degrades to their own key
    // instead of stopping them mid-conversation.
    final client = _RecordingAnthropic();
    final service = _service(
      keys: await _keys(anthropic: 'sk-their-own-key'),
      client: client,
      covered: const {},
    );

    await _run(service);

    expect(client.seen, isA<DirectKey>());
    expect((client.seen as DirectKey).key, 'sk-their-own-key');
  });

  test('no plan and no key still falls back to the mock, as it always did',
      () async {
    final client = _RecordingAnthropic();
    final service = _service(keys: await _keys(), client: client);

    final events = await _run(service);

    expect(client.callCount, 0);
    expect(events.whereType<MessageComplete>(), isNotEmpty,
        reason: 'the turn should still produce an answer');
  });

  test('a covered provider the plan does not include is not used', () async {
    // Coverage is per provider: a plan that includes Gemini does not silently
    // spend an Anthropic key SHIFT holds for someone else's plan.
    final client = _RecordingAnthropic();
    final service = _service(
      keys: await _keys(),
      client: client,
      covered: const {'gemini'},
      managed: _managed,
    );

    await _run(service);

    expect(client.callCount, 0);
  });

  test('a managed call names the proxy, not the provider', () async {
    // The property that makes this worth building: the device never learns a
    // provider key, because it never talks to the provider.
    final resolved = _managed.resolve('/v1/messages');

    expect(resolved.host, 'p.test');
    expect(resolved.path, '/functions/v1/provider-proxy/anthropic/v1/messages');
    expect(resolved.toString(), isNot(contains('anthropic.com')));
  });

  test('a managed Gemini call carries the query the provider needs', () async {
    final gemini = ManagedAccess(
      base: Uri.parse('https://p.test/functions/v1/provider-proxy/gemini'),
      headers: const {},
    );

    final resolved = gemini.resolve(
      '/v1beta/models/gemini-2.5-flash:streamGenerateContent',
      query: const {'alt': 'sse'},
    );

    expect(resolved.queryParameters['alt'], 'sse');
    expect(resolved.path, contains('streamGenerateContent'));
    // No key anywhere in the URL — the proxy attaches it as a header.
    expect(resolved.toString().toLowerCase(), isNot(contains('key=')));
  });
}
