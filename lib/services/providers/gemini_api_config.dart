/// Every Gemini endpoint string and model id in one place. These come from
/// training knowledge rather than live docs, so if Google's API has
/// drifted, this file is the single point of correction — and the
/// Settings key test surfaces raw error bodies to make drift obvious.
class GeminiApiConfig {
  GeminiApiConfig._();

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  static const flashModel = 'gemini-2.5-flash';
  static const proModel = 'gemini-2.5-pro';
  static const imageModel = 'gemini-2.5-flash-image';

  /// SSE streaming chat endpoint.
  static Uri streamEndpoint(String model, String apiKey) =>
      Uri.parse('$_base/models/$model:streamGenerateContent?alt=sse&key=$apiKey');

  /// Non-streaming endpoint (image generation, key validation, routing).
  static Uri generateEndpoint(String model, String apiKey) =>
      Uri.parse('$_base/models/$model:generateContent?key=$apiKey');

  static String displayName(String model) => switch (model) {
        flashModel => 'Gemini 2.5 Flash',
        proModel => 'Gemini 2.5 Pro',
        imageModel => 'Gemini 2.5 Flash Image',
        _ => model,
      };
}
