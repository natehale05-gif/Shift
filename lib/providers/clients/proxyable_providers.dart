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
  'heygen',
  'elevenlabs',
};

/// Whether a membership can pay for this kind of turn.
///
/// **Everything**, now that video, music and voice have hosts in the table and
/// prices to go with them. The line is the proxy's allowlist rather than a
/// preference, and every entry there is a deliberate addition: an allowlist
/// that grew to cover each endpoint a provider offers would not be one, since
/// our own account administration lives on those same hosts.
///
/// The order this arrived in is the useful part. Text first, then pictures,
/// then the asynchronous media — and each gap read, from the phone, as the
/// product being broken rather than as a boundary. A member watched a real
/// page get written and then a procedural gradient appear where a photograph
/// should be.
///
/// Each kind is priced by what it is, on the server: none of these replies
/// carries token counts, and the flat unreported-call charge would bill about
/// a tenth of an image and a fortieth of a video. Status polls are free, which
/// is safe because the allowlist's GET entries only ever read.
///
/// Kept as an exhaustive switch even though every arm is now true. Adding a
/// route should be a decision about whether a membership pays for it, not
/// something a `default` answers on your behalf.
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
      ChatRoute.imageGen ||
      ChatRoute.video ||
      ChatRoute.audio ||
      ChatRoute.voice ||
      ChatRoute.avatar =>
        true,
    };
