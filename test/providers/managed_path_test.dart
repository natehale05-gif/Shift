import 'package:flutter_test/flutter_test.dart';
import 'package:shift/backend/setup_probe.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/clients/gemini_text.dart';
import 'package:shift/providers/clients/openai_image.dart';
import 'package:shift/providers/clients/openai_text.dart';
import 'package:shift/providers/failure_text.dart';
import 'package:shift/providers/probe.dart';
import 'package:shift/providers/registry.dart';
import 'package:shift/turn/capability.dart';

/// The path a managed call takes, and what a refusal from it says.
///
/// Both halves come from one report: *"generate an image of a pink flower"* →
/// **HTTP 403 from …supabase.co** → *"That key was rejected. Check it is
/// complete and still active."*
///
/// The 403 was our own proxy's path allowlist: the client sent
/// `/images/generations` where the server permits `/v1/images/generations`.
/// The sentence was [sentenceForStatus] reading a proxy status as a provider's
/// — advice about a key, to somebody whose whole reason for paying is not
/// holding one.
void main() {
  final managed = ManagedAccess(
    base: Uri.parse('https://p.test/functions/v1/provider-proxy/openai'),
    headers: const {'Authorization': 'Bearer session'},
  );

  /// What the proxy sees after stripping its own prefix — the string
  /// `upstreamUrl` matches against the allowlist.
  String atProvider(Uri uri) =>
      uri.path.replaceFirst('/functions/v1/provider-proxy/openai', '');

  group('the path the proxy is asked for', () {
    test('an image call carries /v1, which is what was missing', () {
      // The reported 403, asserted directly. `/images/generations` matches no
      // entry in the server's list and is refused before anything is spent.
      expect(atProvider(OpenAiImage.target(managed, '').uri),
          '/v1/images/generations');
    });

    test('so does a text call, which broke four providers at once', () {
      // `openai_text` serves OpenAI, Groq, Mistral and OpenRouter, so one
      // missing prefix refused every managed turn on all of them.
      expect(atProvider(OpenAiText.target(managed, '').uri),
          '/v1/chat/completions');
    });

    test('both arms agree on the provider path', () {
      // The bug was not the string, it was that the two arms computed it
      // separately: the direct arm inherits `/v1` from the registry's base URL
      // and the managed arm rebuilt it. Same path either way, or one of them
      // is wrong and only one of them is exercised.
      for (final (base, path) in [
        ('https://api.openai.com/v1', OpenAiText.providerPath),
        ('https://api.openai.com/v1', OpenAiImage.providerPath),
      ]) {
        final direct = OpenAiText.providerPath == path
            ? OpenAiText.target(const DirectKey('k'), base).uri
            : OpenAiImage.target(const DirectKey('k'), base).uri;
        expect(direct.path, path);
      }
    });

    test('the ones that were already right stay right', () {
      // Anthropic and Gemini spell the whole path out, which is why only they
      // ever worked on a membership. Pinned so a tidy-up cannot "simplify"
      // them into the shape that broke the others.
      expect(AnthropicText.providerPath, '/v1/messages');
      expect(
        GeminiText.target(managed, 'gemini-x').uri.path,
        endsWith('/v1beta/models/gemini-x:streamGenerateContent'),
      );
      // Gemini's image path is private to its client, so it is read through
      // the probe, which is the one caller outside it that names a path.
      expect(managedProbeCall(providerById('gemini')!)!.path,
          '/v1beta/models/${providerById('gemini')!.modelFor(Capability.text)!.id}:generateContent');
    });
  });

  group('what the Setup card actually probes', () {
    test('each provider gets its own path, not Claude\'s', () {
      // `probeProxy` sent `/v1/messages` at whatever provider was named, so
      // for five of six the allowlist refused it and the one control built to
      // tell these states apart answered 403 for a provider set up correctly.
      expect(managedProbeCall(providerById('openai')!)!.path,
          '/v1/chat/completions');
      expect(managedProbeCall(providerById('anthropic')!)!.path, '/v1/messages');
      expect(managedProbeCall(providerById('gemini')!)!.path,
          startsWith('/v1beta/models/'));
    });

    test('and the same version header a real Claude turn sends', () {
      // Without it the browser runs a different preflight, which is how this
      // card once reported a proxy working that no turn could reach.
      expect(managedProbeCall(providerById('anthropic')!)!.headers,
          containsPair('anthropic-version', AnthropicText.apiVersion));
    });

    test('a provider with nothing to probe says so rather than guessing', () {
      final imageOnly =
          kProviders.where((p) => !p.can.contains(Capability.text));
      for (final provider in imageOnly) {
        expect(managedProbeCall(provider), isNull, reason: provider.id);
      }
    });
  });

  group('what a refusal from the proxy says', () {
    test('the server\'s own words win, because only it knows which state', () {
      // The exact body behind the report. It named the bug precisely, and the
      // app replaced it with advice about a key.
      expect(
        sentenceForManagedStatus(
            403, '{"message":"That endpoint is not available through SHIFT."}'),
        'That endpoint is not available through SHIFT.',
      );
    });

    test('no managed status blames a key the reader does not have', () {
      // The regression that produced the screenshot, asserted across every
      // status rather than the one that happened to be reported — a new branch
      // must not quietly reintroduce it.
      for (final status in [400, 401, 402, 403, 404, 429, 500, 502, 503, 529]) {
        final sentence = sentenceForManagedStatus(status, '');
        expect(sentence.toLowerCase(), isNot(contains('that key was rejected')),
            reason: '$status');
        expect(sentence.toLowerCase(), isNot(contains('check it is complete')),
            reason: '$status');
      }
    });

    test('an upstream rejection is named as ours to fix, not theirs', () {
      // The proxy passes the provider's status through, so a 401 here means
      // SHIFT's key was refused — nothing the member can do but tell us.
      final sentence = sentenceForManagedStatus(401, '');
      expect(sentence, contains('session'));
      expect(sentenceForManagedStatus(404, ''), contains("SHIFT's own key"));
    });

    test('it agrees with the Setup card on what the server said', () {
      // Two mappings, deliberately: `scan_backend_boundary.py` forbids
      // `backend/` importing `providers/`, and the probe has to live in
      // `backend/`. So neither can call the other, and this is what stops them
      // drifting — a member reading a chat failure and a member reading the
      // Setup card must not be told different things about one status.
      for (final status in [402, 403, 429, 503]) {
        const body = '{"message":"the server said this"}';
        expect(sentenceForManagedStatus(status, body),
            readProxyResponse(status, body).message,
            reason: '$status');
      }

      // And the outcome, not only the words. 403 is the proxy refusing a path
      // of its own; filed as `providerRejected` the card sends someone to
      // check a provider key over a routing mistake — which is the same
      // misattribution in a different place, and the sentence alone does not
      // catch it because both arms quote the server.
      expect(readProxyResponse(403, '').outcome, ProxyOutcome.serverNotReady);
    });

    test('a direct call still reads exactly as it did', () {
      // The guard in the other direction: a genuinely bad personal key must
      // not start reporting as a server problem.
      expect(sentenceForStatus(401),
          'That key was rejected. Check it is complete and still active.');
    });
  });
}
