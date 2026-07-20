import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/attachment.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_request.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/state/api_keys_store.dart';

class _MarkerService implements ChatService {
  final String marker;
  _MarkerService(this.marker);

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) async* {
    yield MessageDelta(marker);
    yield const MessageComplete();
  }
}

Conversation _conversation() => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selector uses mock without a key and real once a key is set',
      () async {
    SharedPreferences.setMockInitialValues({});
    final keys = ApiKeysStore(persistence: PersistenceService());
    await keys.load();

    final selector = ChatServiceSelector(
      keys: keys,
      real: _MarkerService('real'),
      mock: _MarkerService('mock'),
    );

    Future<String> firstChunk() async {
      final events = await selector
          .sendMessage(conversation: _conversation(), userInput: 'hi')
          .toList();
      return events.whereType<MessageDelta>().first.chunk;
    }

    expect(await firstChunk(), 'mock');

    await keys.setAnthropicKey('sk-ant-test');
    expect(await firstChunk(), 'real');

    await keys.setAnthropicKey('');
    expect(await firstChunk(), 'mock');
  });

  test('keys persist across store instances (same persistence)', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    final first = ApiKeysStore(persistence: persistence);
    await first.load();
    await first.setAnthropicKey('sk-ant-persisted');

    final second = ApiKeysStore(persistence: persistence);
    await second.load();
    expect(second.anthropicKey, 'sk-ant-persisted');
    expect(second.anthropicStatus, KeyStatus.untested);
  });

  test('extractCodeArtifact pulls substantial fenced blocks only', () {
    const withCode = '''
Here is your function:

```python
def add(a, b):
    """Adds two numbers."""
    result = a + b
    return result

print(add(1, 2))
```

Hope that helps!
''';
    final artifact = RealChatService.extractCodeArtifact(withCode, 'c1');
    expect(artifact, isNotNull);
    expect(artifact!.language, 'python');
    expect(artifact.latest.content, contains('def add(a, b):'));

    expect(
      RealChatService.extractCodeArtifact('no code here', 'c1'),
      isNull,
    );
    expect(
      RealChatService.extractCodeArtifact('```py\nx = 1\n```', 'c1'),
      isNull,
      reason: 'trivial snippets stay inline',
    );
  });
}
