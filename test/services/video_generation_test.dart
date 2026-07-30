import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/openai_video_client.dart';
import 'package:shift_ai/providers/clients/provider_registry.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/providers/router/provider_selection.dart';
import 'package:shift_ai/providers/streaming/sse_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';

class _ForcedRouter extends ModelRouter {
  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      ChatRoute.video;
}

class _FakeVideoClient extends OpenAiVideoClient {
  int callCount = 0;
  String? seenPrompt;
  final int? failWith;

  _FakeVideoClient({this.failWith});

  @override
  Future<Uint8List> render({
    required String apiKey,
    required String prompt,
    String model = OpenAiVideoClient.defaultModel,
    int seconds = 4,
    String size = '1280x720',
    void Function(VideoJob job)? onProgress,
  }) async {
    callCount++;
    seenPrompt = prompt;
    if (failWith != null) throw SseHttpException(failWith!, '{}');
    return Uint8List.fromList(List.filled(512, 9));
  }
}

Conversation _conversation(String input) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: input,
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 30),
        ),
      ],
    );

Future<(List<ChatEvent>, _FakeVideoClient)> _run({
  bool withKey = true,
  int? failWith,
}) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  if (withKey) await keys.setKey('openai', 'sk-test');
  final client = _FakeVideoClient(failWith: failWith);
  final service = RealChatService(
    keys: keys,
    openAiVideoClient: client,
    router: _ForcedRouter(),
  );
  const prompt = 'a drone shot over a pine forest at sunrise';
  final events = await service
      .sendMessage(conversation: _conversation(prompt), userInput: prompt)
      .toList();
  return (events, client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OpenAI is a video provider now', () {
    // Before this there was no `video` capability on any descriptor, so the
    // route resolved to null and every clip was the simulated card.
    expect(
      chooseProvider(ChatRoute.video,
          registry: ProviderRegistry.defaults(),
          hasKey: (id) => id == 'openai'),
      'openai',
    );
    expect(
      chooseProvider(ChatRoute.video,
          registry: ProviderRegistry.defaults(), hasKey: (_) => false),
      isNull,
    );
  });

  test('a keyed video turn renders for real', () async {
    final (events, client) = await _run();

    expect(client.callCount, 1);
    expect(client.seenPrompt, contains('pine forest'));
    final result =
        events.whereType<StudioResultReady>().single.result as VideoResult;
    expect(result.isRealVideo, isTrue);
    expect(result.videoBytes, isNotNull);
    expect(result.providerLabel, 'Sora');
  });

  test('a failure says why instead of quietly simulating', () async {
    final (events, client) = await _run(failWith: 403);

    expect(client.callCount, 1);
    final text = events.whereType<MessageDelta>().map((d) => d.chunk).join();
    expect(text, contains('rejected the key'));
    // The card still arrives — a silent turn is worse than a simulated clip.
    final result =
        events.whereType<StudioResultReady>().single.result as VideoResult;
    expect(result.isRealVideo, isFalse);
  });

  test('with no key it stays simulated and calls nothing', () async {
    final (events, client) = await _run(withKey: false);

    // The point is the paid endpoint is never touched without a key. What
    // demo mode then makes of the sentence is its own business.
    expect(client.callCount, 0);
    expect(events.whereType<MessageComplete>(), isNotEmpty);
  });

  group('job parsing', () {
    test('the states providers actually use', () {
      expect(parseVideoJob({'id': 'v', 'status': 'completed'}).status,
          VideoJobStatus.completed);
      expect(parseVideoJob({'id': 'v', 'status': 'succeeded'}).status,
          VideoJobStatus.completed);
      expect(parseVideoJob({'id': 'v', 'status': 'queued'}).status,
          VideoJobStatus.queued);
      expect(parseVideoJob({'id': 'v', 'status': 'in_progress'}).status,
          VideoJobStatus.inProgress);
      expect(parseVideoJob({'id': 'v', 'status': 'failed'}).status,
          VideoJobStatus.failed);
    });

    test('an unknown status is still running, never failed', () {
      // A job wrongly called failed throws away work that was finishing.
      expect(parseVideoJob({'id': 'v', 'status': 'whirring'}).status,
          VideoJobStatus.inProgress);
      expect(parseVideoJob({'id': 'v'}).status, VideoJobStatus.inProgress);
    });

    test('the provider error message survives', () {
      expect(
        parseVideoJob({
          'id': 'v',
          'status': 'failed',
          'error': {'message': 'content policy'}
        }).error,
        'content policy',
      );
    });
  });
}
