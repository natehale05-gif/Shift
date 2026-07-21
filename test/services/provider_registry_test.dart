import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/providers/provider_capability.dart';
import 'package:shift_ai/services/providers/provider_descriptor.dart';
import 'package:shift_ai/services/providers/provider_registry.dart';

void main() {
  final registry = ProviderRegistry.defaults();

  group('byId / providerForModel', () {
    test('byId finds the built-in providers and null otherwise', () {
      expect(registry.byId('anthropic')?.displayName, 'Anthropic (Claude)');
      expect(registry.byId('gemini')?.displayName, 'Google Gemini');
      expect(registry.byId('nope'), isNull);
    });

    test('a globally-unique model id resolves back to its provider', () {
      expect(registry.providerForModel('claude-opus-4-8')?.id, 'anthropic');
      expect(registry.providerForModel('claude-haiku-4-5')?.id, 'anthropic');
      expect(registry.providerForModel('gemini-2.5-flash')?.id, 'gemini');
      expect(
          registry.providerForModel('gemini-2.5-flash-image')?.id, 'gemini');
      expect(registry.providerForModel('gpt-4o')?.id, 'openai');
      expect(registry.providerForModel('llama-3.3-70b-versatile')?.id, 'groq');
      expect(registry.providerForModel('mistral-large-latest')?.id, 'mistral');
      expect(registry.providerForModel('openai/gpt-4o')?.id, 'openrouter');
      expect(registry.providerForModel('nope-model'), isNull);
    });
  });

  group('displayNameForModel', () {
    test('maps known model ids to their labels', () {
      expect(
          registry.displayNameForModel('claude-opus-4-8'), 'Claude Opus 4.8');
      expect(registry.displayNameForModel('gemini-2.5-flash-image'),
          'Gemini 2.5 Flash Image');
    });

    test('falls back to the raw id for an unknown model', () {
      expect(registry.displayNameForModel('mystery-model'), 'mystery-model');
    });
  });

  group('providersFor (the Auto order)', () {
    const textOrder = [
      'anthropic',
      'openai',
      'gemini',
      'groq',
      'mistral',
      'openrouter'
    ];

    test('chat is ordered anthropic, openai, gemini, groq, mistral, openrouter',
        () {
      expect(registry.providersFor(ProviderCapability.chat).map((d) => d.id),
          textOrder);
    });

    test('code/writing/routing follow the same order minus Gemini', () {
      // Gemini does not advertise code/writing/routing.
      const noGemini = ['anthropic', 'openai', 'groq', 'mistral', 'openrouter'];
      expect(registry.providersFor(ProviderCapability.code).map((d) => d.id),
          noGemini);
      expect(registry.providersFor(ProviderCapability.writing).map((d) => d.id),
          noGemini);
      expect(registry.providersFor(ProviderCapability.routing).map((d) => d.id),
          noGemini);
    });

    test('image prefers Gemini (LLM providers do not advertise image)', () {
      expect(registry.providersFor(ProviderCapability.image).map((d) => d.id),
          ['gemini']);
    });

    test('search prefers Anthropic, then Gemini', () {
      expect(registry.providersFor(ProviderCapability.search).map((d) => d.id),
          ['anthropic', 'gemini']);
    });

    test('capabilities no built-in provider serves are empty', () {
      expect(registry.providersFor(ProviderCapability.video), isEmpty);
      expect(registry.providersFor(ProviderCapability.avatar), isEmpty);
      expect(registry.providersFor(ProviderCapability.voice), isEmpty);
    });
  });

  group('descriptor helpers', () {
    test('modelsFor filters by explicit vs inherited capabilities', () {
      final gemini = registry.byId('gemini')!;
      // The image model has an explicit {image} capability.
      expect(gemini.modelsFor(ProviderCapability.image).map((m) => m.id),
          ['gemini-2.5-flash-image']);
      // Flash/Pro inherit the provider's chat capability; the image model
      // does not (its capability set is explicit and excludes chat).
      expect(gemini.modelsFor(ProviderCapability.chat).map((m) => m.id),
          ['gemini-2.5-flash', 'gemini-2.5-pro']);
    });

    test('routing model is filtered to routing only', () {
      final anthropic = registry.byId('anthropic')!;
      expect(anthropic.modelsFor(ProviderCapability.routing).map((m) => m.id),
          ['claude-haiku-4-5']);
      // Opus/Sonnet inherit chat; Haiku (explicit {routing}) does not.
      expect(anthropic.modelsFor(ProviderCapability.chat).map((m) => m.id),
          ['claude-opus-4-8', 'claude-sonnet-5']);
    });

    test('defaultModelId is the first chat model', () {
      expect(registry.byId('anthropic')!.defaultModelId, 'claude-opus-4-8');
      expect(registry.byId('gemini')!.defaultModelId, 'gemini-2.5-flash');
    });

    test('persistence key names match the historical constants', () {
      expect(registry.byId('anthropic')!.persistenceKeyName,
          'shift_ai.anthropic_key.v1');
      expect(registry.byId('gemini')!.persistenceKeyName,
          'shift_ai.gemini_key.v1');
    });
  });

  group('ClientRegistry', () {
    test('provides validators for the built-in kinds and caches them', () {
      final clients = ClientRegistry();
      final a1 = clients.validatorFor(ProviderClientKind.anthropic);
      final a2 = clients.validatorFor(ProviderClientKind.anthropic);
      expect(a1, isNotNull);
      expect(identical(a1, a2), isTrue); // cached, one instance per kind
      expect(clients.validatorFor(ProviderClientKind.gemini), isNotNull);
    });

    test('returns a problem string when no client is wired for a kind', () async {
      final clients = ClientRegistry();
      // Flux has no client yet in Phase 0.
      expect(clients.validatorFor(ProviderClientKind.flux), isNull);
      const fluxish = ProviderDescriptor(
        id: 'flux',
        displayName: 'Flux',
        persistenceKeyName: 'shift_ai.flux_key.v1',
        authScheme: AuthScheme.header,
        clientKind: ProviderClientKind.flux,
        capabilities: {ProviderCapability.image},
        models: [],
      );
      final problem = await clients.validateKey(fluxish, 'x');
      expect(problem, isNotNull);
    });

    test('injected factories override the defaults', () async {
      var called = false;
      final clients = ClientRegistry(factories: {
        ProviderClientKind.anthropic: () => _FakeValidator(() => called = true),
      });
      await clients.validateKey(registry.byId('anthropic')!, 'x');
      expect(called, isTrue);
    });
  });
}

class _FakeValidator implements KeyValidatable {
  final void Function() onValidate;
  _FakeValidator(this.onValidate);
  @override
  Future<String?> validateKey(String apiKey) async {
    onValidate();
    return null;
  }
}
