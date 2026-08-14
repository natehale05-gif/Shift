/// The providers SHIFT's own server will forward a call to.
///
/// This is the client's copy of a decision that lives on the server, in the
/// proxy's upstream table. Duplicating it is deliberate and the duplication is
/// checked by `tool/scan_proxy_providers.py`, because the failure when the two
/// drift is silent and expensive: the app offers a provider the server will not
/// forward, the call goes out with no credential, and the provider answers 401
/// — which reads as a bad key rather than as a routing mistake.
///
/// The alternative was asking the server. It is worse: routing has to answer
/// *before* a turn starts, and a round trip buys nothing over a list that
/// cannot drift without failing the build.
///
/// Narrower than v1's, on purpose. v1 lists eight because it has clients for
/// eight; v2 has six providers in its registry and nothing that speaks to
/// HeyGen or ElevenLabs yet. Naming a provider here that the app cannot call
/// would be claiming coverage that does not exist.
const Set<String> proxyableProviders = {
  'anthropic',
  'openai',
  'gemini',
  'groq',
  'mistral',
  'openrouter',
};
