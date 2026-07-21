import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/providers/provider_registry.dart';
import 'package:shift_ai/services/router/model_router.dart';
import 'package:shift_ai/services/router/provider_selection.dart';

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
