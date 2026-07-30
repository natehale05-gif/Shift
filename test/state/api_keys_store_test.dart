import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/provider_capability.dart';
import 'package:shift_ai/providers/clients/provider_registry.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

class _FakeValidator implements KeyValidatable {
  final String? problem;
  int calls = 0;
  _FakeValidator(this.problem);
  @override
  Future<String?> validateKey(String apiKey) async {
    calls++;
    return problem;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ApiKeysStore store({ClientRegistry? clients}) => ApiKeysStore(
        persistence: PersistenceService(),
        clients: clients,
      );

  group('generic API', () {
    test('starts empty, not live', () async {
      final s = store();
      await s.load();
      expect(s.isLive, isFalse);
      expect(s.hasKey('anthropic'), isFalse);
      expect(s.keyFor('anthropic'), '');
      expect(s.statusFor('anthropic'), KeyStatus.none);
    });

    test('setKey stores, marks untested, and flips live', () async {
      final s = store();
      await s.load();
      await s.setKey('anthropic', '  sk-ant-123  ');
      expect(s.keyFor('anthropic'), 'sk-ant-123'); // trimmed
      expect(s.hasKey('anthropic'), isTrue);
      expect(s.statusFor('anthropic'), KeyStatus.untested);
      expect(s.isLive, isTrue);
    });

    test('clearing a key resets status and live', () async {
      final s = store();
      await s.load();
      await s.setKey('gemini', 'AIza-xyz');
      expect(s.isLive, isTrue);
      await s.setKey('gemini', '');
      expect(s.hasKey('gemini'), isFalse);
      expect(s.statusFor('gemini'), KeyStatus.none);
      expect(s.isLive, isFalse);
    });

    test('setKey for an unknown provider is a no-op', () async {
      final s = store();
      await s.load();
      await s.setKey('does-not-exist', 'x');
      expect(s.isLive, isFalse);
    });
  });

  group('testKey', () {
    test('a good key becomes valid', () async {
      final validator = _FakeValidator(null);
      final s = store(
          clients: ClientRegistry(factories: {
        ProviderClientKind.anthropic: () => validator,
      }));
      await s.load();
      await s.setKey('anthropic', 'sk-ant-123');
      await s.testKey('anthropic');
      expect(validator.calls, 1);
      expect(s.statusFor('anthropic'), KeyStatus.valid);
      expect(s.errorFor('anthropic'), isNull);
    });

    test('a bad key becomes invalid and carries the problem', () async {
      final s = store(
          clients: ClientRegistry(factories: {
        ProviderClientKind.gemini: () => _FakeValidator('nope (401)'),
      }));
      await s.load();
      await s.setKey('gemini', 'AIza-bad');
      await s.testKey('gemini');
      expect(s.statusFor('gemini'), KeyStatus.invalid);
      expect(s.errorFor('gemini'), 'nope (401)');
    });

    test('testing an empty key does nothing', () async {
      final validator = _FakeValidator(null);
      final s = store(
          clients: ClientRegistry(factories: {
        ProviderClientKind.anthropic: () => validator,
      }));
      await s.load();
      await s.testKey('anthropic');
      expect(validator.calls, 0);
      expect(s.statusFor('anthropic'), KeyStatus.none);
    });
  });

  group('legacy shims', () {
    test('map onto the generic API by provider id', () async {
      final s = store();
      await s.load();
      await s.setAnthropicKey('sk-ant-1');
      await s.setGeminiKey('AIza-2');
      expect(s.anthropicKey, 'sk-ant-1');
      expect(s.geminiKey, 'AIza-2');
      expect(s.hasAnthropicKey, isTrue);
      expect(s.hasGeminiKey, isTrue);
      expect(s.anthropicStatus, KeyStatus.untested);
      expect(s.geminiStatus, KeyStatus.untested);
      // Generic reads see the same values.
      expect(s.keyFor('anthropic'), 'sk-ant-1');
      expect(s.keyFor('gemini'), 'AIza-2');
    });
  });

  group('persistence round-trip', () {
    test('a key set on one store loads on a fresh store', () async {
      final persistence = PersistenceService();
      final first = ApiKeysStore(persistence: persistence);
      await first.load();
      await first.setKey('anthropic', 'sk-ant-persist');

      final second = ApiKeysStore(persistence: persistence);
      await second.load();
      expect(second.keyFor('anthropic'), 'sk-ant-persist');
      expect(second.hasKey('anthropic'), isTrue);
      expect(second.statusFor('anthropic'), KeyStatus.untested);
    });
  });

  group('pasted keys', () {
    // A key copied off a phone, out of an email, or from a wrapped terminal
    // arrives with whitespace in it. `trim()` alone only cleans the ends, so
    // embedded newlines survived into the x-api-key header and every request
    // came back 401 -- with the app blaming the key rather than the paste.
    Future<ApiKeysStore> store() async {
      SharedPreferences.setMockInitialValues({});
      final s = ApiKeysStore(persistence: PersistenceService());
      await s.load();
      return s;
    }

    test('newlines inside a pasted key are removed', () async {
      final s = await store();
      await s.setKey('anthropic', 'sk-ant-api03-\nAAAA1111\nBBBB2222');
      expect(s.keyFor('anthropic'), 'sk-ant-api03-AAAA1111BBBB2222');
    });

    test('carriage returns, tabs and inner spaces go too', () async {
      final s = await store();
      await s.setKey('anthropic', ' sk-ant\r\n-api03\t- AAAA \n');
      expect(s.keyFor('anthropic'), 'sk-ant-api03-AAAA');
    });

    test('a key that is only whitespace clears the slot', () async {
      final s = await store();
      await s.setKey('anthropic', 'sk-ant-real');
      expect(s.hasKey('anthropic'), isTrue);

      await s.setKey('anthropic', '   \n\t ');
      expect(s.keyFor('anthropic'), isEmpty);
      expect(s.hasKey('anthropic'), isFalse);
      expect(s.statusFor('anthropic'), KeyStatus.none);
    });

    test('a clean key is untouched', () async {
      final s = await store();
      await s.setKey('anthropic', 'sk-ant-api03-cleanKey_123-abc');
      expect(s.keyFor('anthropic'), 'sk-ant-api03-cleanKey_123-abc');
    });

    test('the sanitised form is what persists', () async {
      final persistence = PersistenceService();
      SharedPreferences.setMockInitialValues({});
      final first = ApiKeysStore(persistence: persistence);
      await first.load();
      await first.setKey('anthropic', 'sk-ant-\nwrapped');

      final second = ApiKeysStore(persistence: persistence);
      await second.load();
      expect(second.keyFor('anthropic'), 'sk-ant-wrapped');
    });
  });
}
