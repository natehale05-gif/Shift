import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../turn/chat_service.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'provider_registry.dart';

/// Replicate image generation.
///
/// Replicate is asynchronous by design — create a prediction, poll it, then
/// fetch the output — but it also accepts `Prefer: wait`, which holds the
/// request open until the prediction finishes. That is tried first because it
/// turns the common case into one round trip; the polling loop stays for the
/// runs that exceed the wait window, which is most cold starts.
class ReplicateClient implements KeyValidatable {
  final http.Client Function() _clientFactory;
  final Duration pollInterval;
  final int maxPolls;

  ReplicateClient({
    http.Client Function()? clientFactory,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPolls = 90,
  }) : _clientFactory = clientFactory ?? createStreamingClient;

  static const defaultModel = 'black-forest-labs/flux-schnell';
  static const base = 'https://api.replicate.com/v1';

  static Uri endpoint(String model) =>
      Uri.parse('$base/models/$model/predictions');

  static Map<String, String> headers(String apiKey, {bool wait = false}) => {
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
        if (wait) 'prefer': 'wait',
      };

  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
    String model = defaultModel,
  }) async* {
    final client = _clientFactory();
    try {
      final created = await client.post(
        endpoint(model),
        headers: headers(apiKey, wait: true),
        body: jsonEncode({
          'input': {'prompt': prompt},
        }),
      );
      if (created.statusCode < 200 || created.statusCode >= 300) {
        throw SseHttpException(created.statusCode, created.body);
      }
      var prediction =
          jsonDecode(utf8.decode(created.bodyBytes)) as Map<String, dynamic>;

      // `Prefer: wait` returns the finished prediction when it can; otherwise
      // this is a normal async job and the get URL is on the payload.
      var polls = 0;
      while (!_isTerminal(prediction['status'] as String?) &&
          polls < maxPolls) {
        final getUrl = (prediction['urls'] as Map<String, dynamic>?)?['get']
            as String?;
        if (getUrl == null) break;
        await Future<void>.delayed(pollInterval);
        polls++;
        final poll =
            await client.get(Uri.parse(getUrl), headers: headers(apiKey));
        if (poll.statusCode < 200 || poll.statusCode >= 300) {
          throw SseHttpException(poll.statusCode, poll.body);
        }
        prediction =
            jsonDecode(utf8.decode(poll.bodyBytes)) as Map<String, dynamic>;
      }

      final status = prediction['status'] as String?;
      if (status == 'failed' || status == 'canceled') {
        yield MessageError('Replicate could not generate this image '
            '($status): ${prediction['error'] ?? 'no reason given'}');
        return;
      }
      if (status != 'succeeded') {
        yield const MessageError(
            'Replicate timed out before the image was ready — try again.');
        return;
      }

      final url = _firstOutputUrl(prediction['output']);
      if (url == null) {
        yield const MessageError(
            'Replicate finished but returned no image URL.');
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
        401 || 403 => 'Replicate rejected this token (${e.statusCode}). Find '
            'it at replicate.com/account/api-tokens. Raw response: ${e.body}',
        402 => 'Replicate needs billing set up before it will run a model '
            '(402). Raw response: ${e.body}',
        404 => 'Replicate has no model at that path (404) — the model may '
            'have been renamed. Raw response: ${e.body}',
        429 => 'Replicate rate-limited this token (429).',
        _ => 'Replicate API error ${e.statusCode}: ${e.body}',
      });
    } catch (e) {
      yield MessageError('Could not reach api.replicate.com — a network '
          'filter or CORS may be blocking browser-direct calls. ($e)');
    } finally {
      client.close();
    }
  }

  /// Reads the account the token belongs to. Costs nothing and spends no
  /// prediction, unlike running a model to find out whether the key works.
  @override
  Future<String?> validateKey(String apiKey) async {
    final client = _clientFactory();
    try {
      final response = await client.get(Uri.parse('$base/account'),
          headers: headers(apiKey));
      return switch (response.statusCode) {
        200 => null,
        401 || 403 => 'Replicate rejected this token '
            '(${response.statusCode}). Find it at '
            'replicate.com/account/api-tokens. Raw response: ${response.body}',
        429 => 'Token works but you\'re rate-limited right now (429).',
        _ => 'Replicate API error ${response.statusCode}: ${response.body}',
      };
    } catch (e) {
      return 'Could not reach api.replicate.com — a network filter or CORS '
          'may be blocking browser-direct calls. ($e)';
    } finally {
      client.close();
    }
  }

  static bool _isTerminal(String? status) =>
      status == 'succeeded' || status == 'failed' || status == 'canceled';

  /// Output is a list of URLs for most image models and a bare string for a
  /// few. Reading only the list shape would drop the picture for the others.
  static String? _firstOutputUrl(Object? output) {
    if (output is String && output.isNotEmpty) return output;
    if (output is List && output.isNotEmpty) {
      final first = output.first;
      if (first is String) return first;
    }
    return null;
  }
}
