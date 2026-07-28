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

  /// Live (realtime voice) model id — the Live API is the fastest-moving
  /// part of Gemini, so expect this to need updating; the Live overlay
  /// surfaces raw connection errors for exactly that reason.
  static const liveModel = 'gemini-live-2.5-flash-preview';

  /// BidiGenerateContent WebSocket endpoint for the Live API.
  static Uri liveEndpoint(String apiKey) => Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.'
      'generativelanguage.v1beta.GenerativeService.BidiGenerateContent'
      '?key=$apiKey');

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
