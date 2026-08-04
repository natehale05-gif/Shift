import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/proxyable_providers.dart';
import 'package:shift_ai/providers/router/model_router.dart';

void main() {
  group('what a membership pays for', () {
    test('covers the text routes', () {
      // These are the ones whose endpoints the proxy's allowlist actually
      // forwards. A member with a plan and no key gets real answers, real
      // pages and real code.
      for (final route in [
        ChatRoute.chat,
        ChatRoute.code,
        ChatRoute.writing,
        ChatRoute.webSearch,
        ChatRoute.deepResearch,
      ]) {
        expect(membershipCovers(route), isTrue, reason: '$route');
      }
    });

    test('does not cover the media routes', () {
      // The regression this pins. Image generation, video, music and voice
      // live at endpoints the proxy refuses by design, so treating a
      // membership as usable for them made routing pick a provider whose
      // credential could not be attached — and the provider answered 401,
      // which the app reported as a bad key, for a key the member never had.
      for (final route in [
        ChatRoute.imageGen,
        ChatRoute.video,
        ChatRoute.audio,
        ChatRoute.voice,
        ChatRoute.avatar,
      ]) {
        expect(membershipCovers(route), isFalse, reason: '$route');
      }
    });

    test('every route has an answer', () {
      // The switch is exhaustive, so adding a `ChatRoute` forces a decision
      // about whether a membership pays for it rather than leaving it to
      // whichever default happens to be there.
      for (final route in ChatRoute.values) {
        expect(() => membershipCovers(route), returnsNormally, reason: '$route');
      }
    });

    test('the media providers are not in the proxyable set at all', () {
      // Belt and braces with the route check above: even if a route were
      // misclassified, there is no upstream entry for these, so the server
      // would refuse them.
      for (final provider in ['heygen', 'elevenlabs', 'flux', 'replicate', 'fal']) {
        expect(proxyableProviders.contains(provider), isFalse,
            reason: provider);
      }
    });

    test('the text providers are', () {
      expect(proxyableProviders, contains('anthropic'));
      expect(proxyableProviders, contains('openai'));
      expect(proxyableProviders, contains('gemini'));
    });
  });
}
