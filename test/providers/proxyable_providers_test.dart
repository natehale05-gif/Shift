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

    test('covers images, which is the newest entry', () {
      // Added deliberately, with a per-picture price on the server: an image
      // reply reports no tokens, so the flat unreported-call charge would bill
      // about a tenth of what one costs, and a ceiling that under-counts by
      // 10x does not bound anything.
      expect(membershipCovers(ChatRoute.imageGen), isTrue);
    });

    test('covers video, music and voice too', () {
      // The last three, and the ones that needed most from the server: a host
      // entry each, a second HTTP method so an asynchronous render can be
      // collected, and a price, since none of these replies carries tokens.
      for (final route in [
        ChatRoute.video,
        ChatRoute.audio,
        ChatRoute.voice,
        ChatRoute.avatar,
      ]) {
        expect(membershipCovers(route), isTrue, reason: '$route');
      }
    });

    test('a route cannot be added without deciding', () {
      // Every arm is true today, so the switch looks redundant — it is not.
      // Exhaustiveness is what makes the *next* route a decision rather than
      // something a `default` answers on somebody's behalf, and routing a turn
      // at a provider whose credential cannot be attached is how a 401 came to
      // be reported as a bad key for a key the member never had.
      for (final route in ChatRoute.values) {
        expect(() => membershipCovers(route), returnsNormally, reason: '$route');
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

    test('the image-only hosts are still not proxyable', () {
      // Flux, Replicate and fal have no entry in the proxy's host table, so
      // there is nothing to forward to and routing must never offer them on a
      // membership. `_spendable()` intersects with this set for exactly that
      // reason — the alternative is a call with an empty credential and a 401
      // the app reports as a bad key.
      for (final provider in ['flux', 'replicate', 'fal']) {
        expect(proxyableProviders.contains(provider), isFalse,
            reason: provider);
      }
    });

    test('the media providers that do have hosts are proxyable', () {
      expect(proxyableProviders, contains('heygen'));
      expect(proxyableProviders, contains('elevenlabs'));
    });

    test('the text providers are', () {
      expect(proxyableProviders, contains('anthropic'));
      expect(proxyableProviders, contains('openai'));
      expect(proxyableProviders, contains('gemini'));
    });
  });
}
