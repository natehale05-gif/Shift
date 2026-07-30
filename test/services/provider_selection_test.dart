import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/provider_registry.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/providers/router/provider_selection.dart';

void main() {
  final registry = ProviderRegistry.defaults();

  bool Function(String) only(Set<String> ids) => ids.contains;

  group('chooseProvider (capability-aware Auto)', () {
    test('text routes prefer Claude, then OpenAI, then Gemini', () {
      String? pick(ChatRoute r, Set<String> keys) =>
          chooseProvider(r, registry: registry, hasKey: only(keys));

      expect(pick(ChatRoute.chat, {'anthropic', 'openai', 'gemini'}),
          'anthropic');
      expect(pick(ChatRoute.chat, {'openai', 'gemini'}), 'openai');
      expect(pick(ChatRoute.chat, {'gemini'}), 'gemini');
      expect(pick(ChatRoute.chat, {'groq'}), 'groq');
      expect(pick(ChatRoute.chat, {}), isNull);
    });

    test('an OpenAI-only user still gets a text provider (not the mock)', () {
      expect(chooseProvider(ChatRoute.chat, registry: registry, hasKey: only({'openai'})),
          'openai');
      expect(chooseProvider(ChatRoute.code, registry: registry, hasKey: only({'openai'})),
          'openai');
      expect(chooseProvider(ChatRoute.writing, registry: registry, hasKey: only({'mistral'})),
          'mistral');
    });

    test('a Gemini-only user can build (code no longer falls to the mock)', () {
      // Gemini used not to advertise the code capability, so chooseProvider
      // returned null for a page request and the live backend delegated to the
      // mock -- the user got the simulated demo page while paying for a key.
      expect(chooseProvider(ChatRoute.code, registry: registry, hasKey: only({'gemini'})),
          'gemini');
    });

    test('code preference order holds: Claude, then OpenAI, then Gemini', () {
      String? pick(Set<String> keys) =>
          chooseProvider(ChatRoute.code, registry: registry, hasKey: only(keys));

      expect(pick({'anthropic', 'openai', 'gemini'}), 'anthropic');
      expect(pick({'openai', 'gemini'}), 'openai');
      expect(pick({'gemini', 'groq'}), 'gemini');
      expect(pick({'groq', 'mistral'}), 'groq');
      expect(pick({'mistral', 'openrouter'}), 'mistral');
      expect(pick({'openrouter'}), 'openrouter');
      // No text key at all still means the mock.
      expect(pick({'flux', 'heygen'}), isNull);
      expect(pick({}), isNull);
    });

    test('an OpenAI-only user gets a real image, not the procedural stand-in',
        () {
      // OpenAI has an images endpoint; the other OpenAI-compatible providers
      // do not. Before, image resolved to null for an OpenAI-only user, the
      // backend fell through to the mock, and they got abstract gradient art
      // while the key they had just tested sat unused.
      expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({'openai'})),
          'openai');
    });

    test('image preference: Gemini, Flux, Replicate, fal, then OpenAI', () {
      String? pick(Set<String> keys) =>
          chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only(keys));

      expect(pick({'gemini', 'flux', 'replicate', 'fal', 'openai'}), 'gemini');
      expect(pick({'flux', 'replicate', 'fal', 'openai'}), 'flux');
      expect(pick({'replicate', 'fal', 'openai'}), 'replicate');
      expect(pick({'fal', 'openai'}), 'fal');
      expect(pick({'openai'}), 'openai');
      expect(pick({}), isNull);
    });

    test('each new image provider works on its own', () {
      // A key that resolves to nothing is a key that silently does nothing:
      // the turn falls through to the mock and the user gets demo artwork.
      for (final id in ['replicate', 'fal']) {
        expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({id})),
            id,
            reason: id);
      }
    });

    test('a voiceover now has a real provider to go to', () {
      // Nothing advertised `voice` before ElevenLabs, so every voiceover came
      // from the local synthesizer no matter which keys were present.
      expect(chooseProvider(ChatRoute.voice, registry: registry, hasKey: only({'elevenlabs'})),
          'elevenlabs');
      expect(chooseProvider(ChatRoute.audio, registry: registry, hasKey: only({'elevenlabs'})),
          'elevenlabs');
      expect(chooseProvider(ChatRoute.voice, registry: registry, hasKey: only({'openai'})),
          isNull,
          reason: 'a text key is not a voice key');
    });

    test('a browser skips providers that refuse browser-direct calls', () {
      // Replicate and fal send no CORS headers, so a browser cannot call them
      // however good the key is. Routing there anyway produced a fetch error
      // where a picture was asked for, while a usable OpenAI key sat further
      // down the same list.
      String? pick(Set<String> keys, {required bool onWeb}) => chooseProvider(
          ChatRoute.imageGen,
          registry: registry,
          hasKey: only(keys),
          onWeb: onWeb);

      expect(pick({'replicate', 'openai'}, onWeb: true), 'openai');
      expect(pick({'replicate', 'openai'}, onWeb: false), 'replicate',
          reason: 'the downloaded app has no CORS to answer to');
      expect(pick({'flux', 'gemini'}, onWeb: true), 'gemini');
    });

    test('a browser with only a blocked key gets the mock, not an error', () {
      // Better the simulated card than a fetch failure: the turn at least
      // produces something, and Settings says why the key is idle.
      for (final id in ['replicate', 'fal', 'flux']) {
        expect(
            chooseProvider(ChatRoute.imageGen,
                registry: registry, hasKey: only({id}), onWeb: true),
            isNull,
            reason: id);
      }
    });

    test('off-web nothing is skipped', () {
      // The desktop and mobile apps are not browsers, so every key works.
      for (final id in ['replicate', 'fal', 'flux']) {
        expect(
            chooseProvider(ChatRoute.imageGen,
                registry: registry, hasKey: only({id}), onWeb: false),
            id,
            reason: id);
      }
    });

    test('the providers that do allow browser calls are never skipped', () {
      for (final id in ['gemini', 'openai']) {
        expect(
            chooseProvider(ChatRoute.imageGen,
                registry: registry, hasKey: only({id}), onWeb: true),
            id,
            reason: id);
      }
    });

    test('the voice providers do not accidentally serve image turns', () {
      expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({'elevenlabs'})),
          isNull);
    });

    test('the other OpenAI-compatible providers still have no image endpoint',
        () {
      for (final id in ['groq', 'mistral', 'openrouter']) {
        expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({id})),
            isNull,
            reason: id);
      }
    });

    test('search resolves to Anthropic then Gemini; OpenAI-only degrades', () {
      expect(chooseProvider(ChatRoute.webSearch, registry: registry, hasKey: only({'anthropic', 'gemini'})),
          'anthropic');
      expect(chooseProvider(ChatRoute.webSearch, registry: registry, hasKey: only({'gemini'})),
          'gemini');
      // No search-capable key → null (deep research degrades to plain
      // completion).
      expect(chooseProvider(ChatRoute.webSearch, registry: registry, hasKey: only({'openai'})),
          isNull);
    });

    test('video renders on OpenAI, and on nothing else', () {
      // Video had no provider at all, so every clip was the simulated card
      // however many keys were present. OpenAI renders it now; the others
      // still cannot, so a Gemini-or-Groq user keeps the simulation.
      expect(
          chooseProvider(ChatRoute.video,
              registry: registry, hasKey: only({'openai'})),
          'openai');
      for (final keys in [<String>{}, {'anthropic', 'gemini', 'groq'}]) {
        expect(chooseProvider(ChatRoute.video, registry: registry, hasKey: only(keys)),
            isNull);
      }
    });

    test('audio still needs a voice key', () {
      expect(
          chooseProvider(ChatRoute.audio,
              registry: registry, hasKey: only({'elevenlabs'})),
          'elevenlabs');
      expect(
          chooseProvider(ChatRoute.audio,
              registry: registry, hasKey: only({'anthropic', 'gemini'})),
          isNull);
    });
  });

  group('capabilityForRoute', () {
    test('maps every route to a capability', () {
      // Just exercise all arms so an added route forces a decision here too.
      for (final route in ChatRoute.values) {
        expect(() => capabilityForRoute(route), returnsNormally);
      }
    });
  });
}
