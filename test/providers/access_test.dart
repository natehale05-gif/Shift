import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';

Uri proxy(String provider) =>
    Uri.parse('https://example.test/functions/v1/provider-proxy/$provider');

Map<String, String> session() => {'Authorization': 'Bearer session-token'};

ProviderAccess? resolve(
  String provider, {
  Entitlement entitlement = Entitlement.none,
  String? ownKey,
}) =>
    resolveAccess(
      provider,
      entitlement: entitlement,
      ownKey: ownKey,
      proxyBase: proxy,
      sessionHeaders: session,
    );

const _paidForText = Entitlement(
  canSpendManaged: true,
  includedProviders: {'anthropic'},
);

void main() {
  group('membership first, own key second', () {
    test('an active plan is spent even when the user also has a key', () {
      // The decision, stated as a test: they pay monthly, so the plan should
      // be the thing that gets used. If this ever flips, someone is paying a
      // subscription and their own provider bill at the same time.
      final access =
          resolve('anthropic', entitlement: _paidForText, ownKey: 'sk-ant-own');
      expect(access, isA<ManagedAccess>());
      expect((access! as ManagedAccess).base.path, contains('anthropic'));
    });

    test('the key never leaves the device on the managed path', () {
      // The custody argument for the subscription. A ManagedAccess carries a
      // session token; the provider credential is injected server-side and is
      // never in the client's hands at all.
      final access =
          resolve('anthropic', entitlement: _paidForText, ownKey: 'sk-ant-own')!
              as ManagedAccess;
      expect(access.headers.values.join(), isNot(contains('sk-ant-own')));
    });

    test('over the ceiling falls back to the user\'s own key', () {
      // Degrading rather than stopping is the whole point of having both.
      // `canSpendManaged` is false once the ceiling is hit, and the turn keeps
      // working instead of turning into a billing message mid-sentence.
      final spent = Entitlement(
        canSpendManaged: false,
        includedProviders: _paidForText.includedProviders,
      );
      final access =
          resolve('anthropic', entitlement: spent, ownKey: 'sk-ant-own');
      expect(access, isA<DirectKey>());
      expect((access! as DirectKey).key, 'sk-ant-own');
    });

    test('a provider outside the plan uses the own key, not the proxy', () {
      // A plan covering text but not images is an ordinary shape. Sending an
      // image call to the proxy would spend SHIFT's money on something the
      // plan never sold.
      final access =
          resolve('gemini', entitlement: _paidForText, ownKey: 'AIza-own');
      expect(access, isA<DirectKey>());
    });
  });

  group('neither', () {
    test('no plan and no key is null, not an empty credential', () {
      expect(resolve('anthropic'), isNull);
    });

    test('an empty key is treated as no key', () {
      // A cleared text field leaves '' behind. Sending it produces a 401 that
      // reads as "your key is wrong" when the truth is there is no key.
      expect(resolve('anthropic', ownKey: ''), isNull);
    });

    test('a plan that covers nothing does not reach for the proxy', () {
      const empty = Entitlement(canSpendManaged: true);
      expect(resolve('anthropic', entitlement: empty), isNull);
    });
  });
}
