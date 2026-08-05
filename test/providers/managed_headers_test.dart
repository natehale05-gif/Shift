import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/anthropic_api_config.dart';
import 'package:shift_ai/providers/clients/provider_registry.dart';

/// What a browser may send to any origin without asking permission first,
/// plus the two the proxy's own preflight allow list names.
///
/// Anything outside this set triggers a CORS preflight that the server has to
/// allow by name. The proxy does allow them now — it reflects whatever is
/// asked for — but that change is a deploy, and a deploy is the one thing this
/// project keeps not being able to do on demand. So the client stays inside
/// the set that works against a proxy that has not been redeployed since.
const _alwaysAllowed = {
  'accept',
  'accept-language',
  'content-language',
  'content-type',
  'authorization',
  'apikey',
};

void main() {
  group('a managed call sends nothing the browser has to ask permission for',
      () {
    // Two headers have now cost two providers their entire live path, found
    // one at a time by a turn failing on a phone:
    //
    //   `anthropic-version`             — every managed Anthropic turn
    //   `HTTP-Referer` / `X-Title`      — every managed OpenRouter turn
    //
    // Both were the same mistake: the device announcing a provider's wire
    // format on a call it is not paying for. This test is here so the third
    // one fails in CI instead.

    test('Anthropic', () {
      for (final name in AnthropicApiConfig.headers(null).keys) {
        expect(_alwaysAllowed, contains(name.toLowerCase()),
            reason: '$name forces a preflight the proxy must allow by name');
      }
    });

    test('no provider carries extra headers into a managed call', () {
      // `extraHeaders` is per-provider identification — OpenRouter's today,
      // somebody else's tomorrow. Whatever a descriptor declares belongs to
      // the key being spent, so on a membership it is the server's to attach.
      // The clients drop it for managed calls; this asserts the reason still
      // holds by showing at least one provider declares some, so the rule is
      // not vacuously true.
      final registry = ProviderRegistry.defaults();
      final withExtras =
          registry.all.where((d) => d.extraHeaders.isNotEmpty).toList();

      expect(withExtras, isNotEmpty,
          reason: 'if no provider declares extra headers any more, this test '
              'has stopped guarding anything and should be re-aimed');

      for (final descriptor in withExtras) {
        for (final name in descriptor.extraHeaders.keys) {
          expect(_alwaysAllowed.contains(name.toLowerCase()), isFalse,
              reason: '${descriptor.id} declares $name, which is exactly the '
                  'kind of header that must not ride on a managed call');
        }
      }
    });
  });
}
