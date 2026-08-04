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
/// **Text only, and that is not an oversight.** The proxy's allowlist is
/// `/v1/messages`, `/v1/chat/completions`, `/v1/responses` and Gemini's
/// `generateContent` — the chat endpoints. Image generation, video, music and
/// voice all live at other paths on the same hosts, and the proxy refuses them
/// by design: an allowlist that grew to cover every endpoint a provider offers
/// would not be an allowlist.
///
/// So a member with a plan and no key of their own gets real answers, real
/// pages and real code, and still falls back to the simulation for media. That
/// is a real limit and the app says so rather than routing a media turn at a
/// credential it cannot attach — which produced a 401 blaming the member's key
/// for a key they never had.
bool membershipCovers(ChatRoute route) => switch (route) {
      ChatRoute.chat ||
      ChatRoute.code ||
      ChatRoute.writing ||
      ChatRoute.webSearch ||
      ChatRoute.deepResearch ||
      ChatRoute.translate ||
      ChatRoute.deck ||
      ChatRoute.shortReels ||
      ChatRoute.brandPack =>
        true,
      // Every one of these needs an endpoint the proxy does not forward.
      ChatRoute.imageGen ||
      ChatRoute.video ||
      ChatRoute.audio ||
      ChatRoute.voice ||
      ChatRoute.avatar =>
        false,
    };
