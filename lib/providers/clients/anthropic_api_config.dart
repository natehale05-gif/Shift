/// Every Anthropic endpoint string, header, and model id in one place, so
/// API drift is a one-file fix.
class AnthropicApiConfig {
  AnthropicApiConfig._();

  static final Uri messagesEndpoint =
      Uri.parse('https://api.anthropic.com/v1/messages');

  static const apiVersion = '2023-06-01';

  /// Default model for chat, code, and writing — the most capable tier.
  static const defaultModel = 'claude-opus-4-8';
  static const sonnetModel = 'claude-sonnet-5';

  /// Small fast model: routing classification and key validation.
  static const haikuModel = 'claude-haiku-4-5';

  static const availableModels = [defaultModel, sonnetModel, haikuModel];

  /// Models that support (and default to) adaptive extended thinking.
  static const thinkingModels = {defaultModel, sonnetModel};

  static const defaultMaxTokens = 16000;

  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': apiVersion,
        // Required for browser-direct calls (CORS): the user supplied their
        // own key and accepts that it lives client-side.
        'anthropic-dangerous-direct-browser-access': 'true',
      };

  static String displayName(String model) => switch (model) {
        defaultModel => 'Claude Opus 4.8',
        sonnetModel => 'Claude Sonnet 5',
        haikuModel => 'Claude Haiku 4.5',
        _ => model,
      };
}
