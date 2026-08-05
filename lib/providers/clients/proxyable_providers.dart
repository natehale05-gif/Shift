import '../router/model_router.dart';

/// The providers SHIFT's server will forward a call to, and the routes it will
/// forward.
///
/// This is the client's copy of a decision that lives on the server, in the
/// proxy's own upstream table (`_shared/upstream.js`, beside the edge
/// functions — deliberately not named by path here, because the boundary scan
/// is right that nothing outside `lib/backend/` should know which host runs
/// it).
///
/// Duplicating it is deliberate and the duplication is checked:
/// `tool/scan_proxy_providers.py` fails the build if the two lists drift,
/// because the failure mode when they do is silent and expensive — the app
/// offers a provider the server will not forward, the call goes out with no
/// credential, and the provider answers 401, which reads as a bad key rather
/// than as a routing mistake.
///
/// The alternative was asking the server. It is worse: routing has to answer
/// *now*, before a turn starts, and a round trip on every keystroke-adjacent
/// decision buys nothing over a list that cannot drift.
const Set<String> proxyableProviders = {
  'anthropic',
  'openai',
  'gemini',
  'groq',
  'mistral',
  'openrouter',
};

/// Whether a membership can pay for this kind of turn.
///
/// **Text and pictures, not video or sound**, and the line is the proxy's
/// allowlist rather than a preference: `/v1/messages`,
/// `/v1/chat/completions`, `/v1/responses`, `/v1/images/generations`, and
/// Gemini's `generateContent`. Each entry is a deliberate addition. An
/// allowlist that grew to cover every endpoint a provider offers would not be
/// an allowlist — our own account administration lives on those same hosts.
///
/// Images were the last thing a membership did not buy, and their absence read
/// as the product being broken rather than as a boundary: a member watched a
/// real page get written and then a procedural gradient appear where a
/// photograph should be. They are priced per picture on the server, because an
/// image reply reports no tokens and the flat fallback charge would bill about
/// a tenth of what one costs.
///
/// Video, music, voice and avatars stay out, and not only for want of an
/// allowlist entry: HeyGen, ElevenLabs, Flux, Replicate and fal are not in the
/// proxy's host table at all, so there is nothing to forward to. Those remain
/// the member's own key.
bool membershipCovers(ChatRoute route) => switch (route) {
      ChatRoute.chat ||
      ChatRoute.code ||
      ChatRoute.writing ||
      ChatRoute.webSearch ||
      ChatRoute.deepResearch ||
      ChatRoute.translate ||
      ChatRoute.deck ||
      ChatRoute.shortReels ||
      ChatRoute.brandPack ||
      ChatRoute.imageGen =>
        true,
      // Every one of these needs a host the proxy does not know.
      ChatRoute.video ||
      ChatRoute.audio ||
      ChatRoute.voice ||
      ChatRoute.avatar =>
        false,
    };
