/// Every route this app asks SHIFT's proxy to forward.
///
/// **Why this exists as a list at all.** The clients already know their own
/// paths, and `tool/scan_proxy_providers.py` already checks those against the
/// server's allowlist — *the one in this repository*. That check is green while
/// the product is broken, because the repository is not what is running: the
/// deployed proxy sat five commits behind for a week, with no image route, and
/// the only symptom was a member's failed turn reported as a rejected key.
///
/// So the app needs to be able to state its requirement to a *running* server
/// and be told yes or no. That is what this is: the requirement, in the same
/// `'METHOD /prefix'` form the server's allowlist uses, so the comparison is a
/// set operation rather than an interpretation.
///
/// **It is a checked mirror, not a fourth hand-written list.** The scan derives
/// each client's path and which providers that client serves, and fails the
/// build unless every derived path is covered by an entry here *and* every
/// entry here appears verbatim in the server's own table. A route the app
/// stopped needing, or started needing, cannot go unrecorded.
///
/// Prefixes rather than whole paths, matching the server: Gemini's path carries
/// a model id and a method suffix, so `/v1beta/models/` is the most that can be
/// stated in advance — which is exactly what the server matches on.
const Map<String, List<String>> requiredProxyRoutes = {
  'anthropic': ['POST /v1/messages'],
  'openai': [
    'POST /v1/chat/completions',
    'POST /v1/images/generations',
    // Claimed ahead of any client that builds it: editing a photo sends a
    // multipart body, and the app doing that is being built separately against
    // this same proxy. The scan does not force this entry — it checks
    // client -> here, and here -> the allowlist in this repo, never the
    // reverse — so it is here to make Settings > Check report a server that
    // lacks the route as behind, which is the only way that drift is visible.
    //
    // Apostrophes are deliberately absent from this comment: the scan reads
    // the list with a regex over quoted strings, so one would be parsed as a
    // route and fail the build.
    'POST /v1/images/edits',
  ],
  'gemini': ['POST /v1beta/models/'],
  'groq': ['POST /v1/chat/completions'],
  'mistral': ['POST /v1/chat/completions'],
  'openrouter': ['POST /v1/chat/completions'],
};
