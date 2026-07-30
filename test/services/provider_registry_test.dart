import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/provider_capability.dart';
import 'package:shift_ai/providers/clients/provider_descriptor.dart';
import 'package:shift_ai/providers/clients/provider_registry.dart';

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

    test('code follows the same order as chat', () {
      // Gemini advertises code alongside chat: without it, a Gemini-only user
      // asking for a page matched no code-capable provider and fell through to
      // the simulated demo page.
      expect(registry.providersFor(ProviderCapability.code).map((d) => d.id),
          textOrder);
    });

    test('writing/routing follow the same order minus Gemini', () {
      // Gemini does not advertise writing/routing.
      const noGemini = ['anthropic', 'openai', 'groq', 'mistral', 'openrouter'];
      expect(registry.providersFor(ProviderCapability.writing).map((d) => d.id),
          noGemini);
      expect(registry.providersFor(ProviderCapability.routing).map((d) => d.id),
          noGemini);
    });

    test('image prefers the dedicated providers, then OpenAI', () {
      // OpenAI joins the list because it has an images endpoint, behind the
      // two providers that do nothing else. Groq, Mistral and OpenRouter share
      // OpenAI's *chat* shape, not its images endpoint, so they stay out.
      expect(registry.providersFor(ProviderCapability.image).map((d) => d.id),
          ['gemini', 'flux', 'replicate', 'fal', 'openai']);
    });

    test('search prefers Anthropic, then Gemini', () {
      expect(registry.providersFor(ProviderCapability.search).map((d) => d.id),
          ['anthropic', 'gemini']);
    });

    test('avatar is Heygen, video is OpenAI, voice is ElevenLabs', () {
      expect(registry.providersFor(ProviderCapability.avatar).map((d) => d.id),
          ['heygen']);
      // Video used to be empty, which is why every clip was simulated. A
      // talking head is still Heygen's — that is the avatar capability, and a
      // different thing from rendering a scene from a prompt.
      expect(registry.providersFor(ProviderCapability.video).map((d) => d.id),
          ['openai']);
      // Voice is no longer empty: ElevenLabs speaks, so a voiceover can come
      // from a real voice instead of the local synthesizer.
      expect(registry.providersFor(ProviderCapability.voice).map((d) => d.id),
          ['elevenlabs']);
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

    test('returns a problem string when an OpenAI-compatible provider is '
        'misconfigured (no base URL / model)', () async {
      final clients = ClientRegistry();
      const broken = ProviderDescriptor(
        id: 'broken',
        displayName: 'Broken',
        persistenceKeyName: 'shift_ai.broken_key.v1',
        authScheme: AuthScheme.header,
        clientKind: ProviderClientKind.openAiCompatible,
        capabilities: {ProviderCapability.chat},
        models: [], // no default model, no base URL
      );
      final problem = await clients.validateKey(broken, 'x');
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
