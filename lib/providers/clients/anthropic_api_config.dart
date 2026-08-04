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

  /// Output ceiling for a code-routed turn.
  ///
  /// A single-file responsive website runs to hundreds of lines, and extended
  /// thinking spends from the same budget — so 16000 truncated real "build me
  /// a website" replies, which the client reports as MessageIncomplete. The
  /// ceiling is a limit, not a reservation: billing is on tokens actually
  /// produced, so raising it costs nothing on the turns that never approach
  /// it and stops the deliverable arriving half-written on the ones that do.
  static const codeMaxTokens = 48000;

  /// [apiKey] is null for a call going through SHIFT's proxy, which attaches
  /// the credential itself. The browser-direct opt-out goes with it: that
  /// header exists to say "this device is knowingly holding a key", and a
  /// managed call is precisely the arrangement where it is not.
  /// The headers for a call to Anthropic, or — when [apiKey] is null — for a
  /// call to SHIFT's proxy on a membership.
  ///
  /// **A managed call sends neither the key nor the version**, and the second
  /// half of that is not tidiness. Every header beyond the CORS-simple set
  /// makes the browser preflight, and the preflight has to be allowed by the
  /// server being called. `anthropic-version` was not on that list, so the
  /// browser blocked the request before it left the device and the app
  /// reported "could not reach the provider" — about a provider it had never
  /// been allowed to ask.
  ///
  /// Omitting it is safe rather than lucky: the proxy sets
  /// `anthropic-version` itself when the incoming request has none, precisely
  /// so a member's device does not have to know a provider's wire format to
  /// spend a membership. The provider's requirements are the proxy's business.
  static Map<String, String> headers(String? apiKey) => {
        'content-type': 'application/json',
        if (apiKey != null) ...{
          'x-api-key': apiKey,
          'anthropic-version': apiVersion,
          'anthropic-dangerous-direct-browser-access': 'true',
        },
      };

  static String displayName(String model) => switch (model) {
        defaultModel => 'Claude Opus 4.8',
        sonnetModel => 'Claude Sonnet 5',
        haikuModel => 'Claude Haiku 4.5',
        _ => model,
      };
}
