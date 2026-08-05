import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../turn/chat_service.dart';
import 'provider_access.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';

/// OpenAI image generation (`POST /v1/images/generations`).
///
/// Deliberately *not* part of [OpenAiCompatibleClient]: that client exists
/// because OpenAI, Groq, OpenRouter and Mistral all speak the same
/// chat-completions shape. The images endpoint is not part of that shape —
/// the OpenAI-compatible providers do not implement it — so this is a client
/// for OpenAI alone, and only OpenAI's descriptor declares the image
/// capability.
///
/// Two response shapes are handled because the models disagree: `gpt-image-1`
/// always returns base64 in `b64_json`, while the DALL·E models return a
/// signed `url` unless asked otherwise. Reading both means a model swap cannot
/// silently produce a blank image.
class OpenAiImageClient {
  final http.Client Function() _clientFactory;

  OpenAiImageClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

  static const defaultModel = 'gpt-image-1';

  static Uri endpoint(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed/images/generations');
  }

  /// Whether [model] accepts the `response_format` parameter.
  ///
  /// gpt-image-1 does not merely ignore it — it rejects the whole request with
  /// `400 Unknown parameter: 'response_format'`. It is always base64, so it
  /// has no format to choose. The DALL·E models default to a signed URL and do
  /// need to be asked.
  static bool wantsResponseFormat(String model) => model.startsWith('dall-e');

  static Map<String, dynamic> buildRequestBody({
    required String prompt,
    String model = defaultModel,
    String size = '1024x1024',
  }) =>
      {
        'model': model,
        'prompt': prompt,
        'n': 1,
        'size': size,
        if (wantsResponseFormat(model)) 'response_format': 'b64_json',
      };

  /// Generates one image and maps it onto the same
  /// [ImageGenerated] → ImageBlock path Gemini and Flux use.
  Stream<ChatEvent> generateImage({
    required ProviderAccess access,
    required String prompt,
    String baseUrl = 'https://api.openai.com/v1',
    String model = defaultModel,
    String size = '1024x1024',
  }) async* {
    // The same two shapes every other client takes: the member's own key
    // straight to OpenAI, or SHIFT's key attached at the proxy. Images were
    // the last path still assuming the first, which is why a membership
    // covered words and not pictures.
    final (uri, headers) = switch (access) {
      DirectKey(:final key) => (
          endpoint(baseUrl),
          {
            'content-type': 'application/json',
            'Authorization': 'Bearer $key',
          },
        ),
      ManagedAccess(:final base, headers: final auth) => (
          ManagedAccess(base: base, headers: const {})
              .resolve('/v1/images/generations'),
          {'content-type': 'application/json', ...auth},
        ),
    };

    final client = _clientFactory();
    try {
      final response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(
            buildRequestBody(prompt: prompt, model: model, size: size)),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SseHttpException(response.statusCode, response.body);
      }
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final data = payload['data'];
      final first = data is List && data.isNotEmpty ? data.first : null;
      if (first is! Map) {
        yield const MessageError(
            'OpenAI returned no image for this prompt — try rewording it.');
        return;
      }

      Uint8List? bytes;
      final encoded = first['b64_json'] as String?;
      if (encoded != null && encoded.isNotEmpty) {
        bytes = base64Decode(encoded);
      } else {
        final url = first['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final image = await client.get(Uri.parse(url));
          if (image.statusCode < 200 || image.statusCode >= 300) {
            throw SseHttpException(image.statusCode, image.body);
          }
          bytes = image.bodyBytes;
        }
      }
      if (bytes == null) {
        yield const MessageError(
            'OpenAI returned an image entry with no data — the API may have '
            'changed.');
        return;
      }

      yield ImageGenerated(pngBytes: bytes, alt: prompt);
      yield const MessageComplete();
    } on SseHttpException catch (e) {
      // Worth naming the two that actually happen: an org that has not
      // verified cannot call gpt-image-1 at all, and image calls bill
      // separately from chat, so a working chat key can still be out of
      // credit here.
      yield MessageError(switch (e.statusCode) {
        401 || 403 => 'OpenAI rejected this key for image generation '
            '(${e.statusCode}). Image models need a verified organization — '
            'check platform.openai.com → Settings → Organization. '
            'Raw response: ${e.body}',
        429 => 'OpenAI rate-limited or out of credit for images (429). Image '
            'generation bills separately from chat. Raw response: ${e.body}',
        _ => 'OpenAI image API error ${e.statusCode}: ${e.body}',
      });
    } catch (e) {
      yield MessageError('Could not reach api.openai.com for image '
          'generation — a network filter or CORS may be blocking it. ($e)');
    } finally {
      client.close();
    }
  }
}
