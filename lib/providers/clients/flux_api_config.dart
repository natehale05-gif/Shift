/// Black Forest Labs (FLUX) endpoints and model ids in one place. The FLUX API
/// is asynchronous: POST a generation request to a per-model path, then poll
/// `get_result` until a signed sample URL is ready.
class FluxApiConfig {
  FluxApiConfig._();

  static const base = 'https://api.bfl.ai/v1';

  /// Per-model submit paths double as the model ids (globally unique).
  static const proModel = 'flux-pro-1.1';
  static const devModel = 'flux-dev';

  static const defaultModel = proModel;
  static const availableModels = [proModel, devModel];

  /// Submit endpoint for a model (the path is the model id).
  static Uri submitEndpoint(String model) => Uri.parse('$base/$model');

  /// Result-polling endpoint for a submitted job id.
  static Uri resultEndpoint(String id) => Uri.parse('$base/get_result?id=$id');

  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-key': apiKey,
      };

  static String displayName(String model) => switch (model) {
        proModel => 'FLUX 1.1 Pro',
        devModel => 'FLUX.1 dev',
        _ => model,
      };
}
