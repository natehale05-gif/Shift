/// Shared endpoint shape for OpenAI-compatible providers (OpenAI, Groq,
/// OpenRouter, Mistral). Every provider differs only by base URL, model list,
/// and extra headers — all carried on the [ProviderDescriptor] — so this file
/// holds just the invariant path and header names.
class OpenAiCompatibleConfig {
  OpenAiCompatibleConfig._();

  static const chatCompletionsPath = '/chat/completions';

  /// Builds the chat-completions endpoint for a provider base URL. Trailing
  /// slashes on [baseUrl] are tolerated.
  static Uri chatCompletionsEndpoint(String baseUrl) {
    final trimmed =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$trimmed$chatCompletionsPath');
  }

  /// The base headers for a request: JSON content type + bearer auth, then the
  /// provider's [extraHeaders] (e.g. OpenRouter's HTTP-Referer / X-Title).
  static Map<String, String> headers(
    String apiKey, {
    Map<String, String> extraHeaders = const {},
  }) =>
      {
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
        ...extraHeaders,
      };
}
