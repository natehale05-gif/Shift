import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../turn/chat_service.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'provider_registry.dart';

/// fal.ai image generation.
///
/// The simplest of the three image providers to talk to: `fal.run` is
/// synchronous, so one POST returns the finished image's URL. No job id, no
/// polling loop — unlike Flux and Replicate.
class FalClient implements KeyValidatable {
  final http.Client Function() _clientFactory;

  FalClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

  /// FLUX.1 [schnell] — fast and cheap, which matters when the picture appears
  /// inline in a chat rather than in a render queue.
  static const defaultModel = 'fal-ai/flux/schnell';
  static const base = 'https://fal.run';

  static Uri endpoint(String model) => Uri.parse('$base/$model');

  /// fal's own scheme, not Bearer — `Key <token>`.
  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'authorization': 'Key $apiKey',
      };

  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
    String model = defaultModel,
  }) async* {
    final client = _clientFactory();
    try {
      final response = await client.post(
        endpoint(model),
        headers: headers(apiKey),
        body: jsonEncode({'prompt': prompt, 'num_images': 1}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SseHttpException(response.statusCode, response.body);
      }
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final url = _firstImageUrl(payload);
      if (url == null) {
        yield const MessageError(
            'fal returned no image for this prompt — try rewording it.');
        return;
      }
      final image = await client.get(Uri.parse(url));
      if (image.statusCode < 200 || image.statusCode >= 300) {
        throw SseHttpException(image.statusCode, image.body);
      }
      yield ImageGenerated(
          pngBytes: Uint8List.fromList(image.bodyBytes), alt: prompt);
      yield const MessageComplete();
    } on SseHttpException catch (e) {
      yield MessageError(switch (e.statusCode) {
        401 || 403 => 'fal rejected this key (${e.statusCode}). Create one at '
            'fal.ai/dashboard/keys. Raw response: ${e.body}',
        422 => 'fal could not use this prompt (422). Raw response: ${e.body}',
        429 => 'fal rate-limited or out of credit (429).',
        _ => 'fal API error ${e.statusCode}: ${e.body}',
      });
    } catch (e) {
      yield MessageError('Could not reach fal.run — a network filter or CORS '
          'may be blocking browser-direct calls. ($e)');
    } finally {
      client.close();
    }
  }

  /// Probes the model endpoint with a body it will reject for a *validation*
  /// reason rather than an auth one, so a good key answers 422 and a bad one
  /// 401/403. fal has no free "who am I" endpoint, and generating a throwaway
  /// image to test a key would spend the user's credit to answer a question
  /// the status code already answers.
  @override
  Future<String?> validateKey(String apiKey) async {
    final client = _clientFactory();
    try {
      final response = await client.post(
        endpoint(defaultModel),
        headers: headers(apiKey),
        body: jsonEncode(const <String, Object?>{}),
      );
      return switch (response.statusCode) {
        401 || 403 => 'fal rejected this key (${response.statusCode}). Create '
            'one at fal.ai/dashboard/keys. Raw response: ${response.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        // 422 = authorized, prompt missing. Anything else non-auth means the
        // key got through.
        _ => null,
      };
    } catch (e) {
      return 'Could not reach fal.run — a network filter or CORS may be '
          'blocking browser-direct calls. ($e)';
    } finally {
      client.close();
    }
  }

  /// fal models disagree on the response shape — some return `images`, some a
  /// single `image` — so both are read rather than assuming one model's.
  static String? _firstImageUrl(Map<String, dynamic> payload) {
    final images = payload['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) return first['url'] as String?;
      if (first is String) return first;
    }
    final single = payload['image'];
    if (single is Map) return single['url'] as String?;
    if (single is String) return single;
    return null;
  }
}
