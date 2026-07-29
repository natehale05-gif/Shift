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

    test('image only ever resolves to Gemini (or nothing)', () {
      expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({'gemini'})),
          'gemini');
      // OpenAI-compatible providers do not advertise image → no live image.
      expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({'openai'})),
          isNull);
      expect(chooseProvider(ChatRoute.imageGen, registry: registry, hasKey: only({})),
          isNull);
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

    test('video and audio have no live provider', () {
      for (final keys in [<String>{}, {'anthropic', 'gemini', 'openai', 'groq'}]) {
        expect(chooseProvider(ChatRoute.video, registry: registry, hasKey: only(keys)),
            isNull);
        expect(chooseProvider(ChatRoute.audio, registry: registry, hasKey: only(keys)),
            isNull);
      }
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
