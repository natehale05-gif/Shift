import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../services/chat_service.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'flux_api_config.dart';
import 'provider_registry.dart';

/// Raw-HTTP Black Forest Labs (FLUX) client. The API is asynchronous —
/// submit → poll → fetch the signed sample URL — so [generateImage] drives
/// that loop and maps the final PNG onto the app's [ImageGenerated] event,
/// fitting the same ImageGenerated → ImageBlock path Gemini uses. Raw error
/// bodies are surfaced (CORS/endpoint drift on this provider is likely).
class FluxClient implements KeyValidatable {
  final http.Client Function() _clientFactory;
  final Duration pollInterval;
  final int maxPolls;

  FluxClient({
    http.Client Function()? clientFactory,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPolls = 60,
  }) : _clientFactory = clientFactory ?? createStreamingClient;

  /// Generates one image: submit the prompt, poll until the result is Ready,
  /// then fetch the sample bytes. Emits [ImageGenerated] + [MessageComplete] on
  /// success, or [MessageError] with the raw problem otherwise.
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
    String model = FluxApiConfig.defaultModel,
    int width = 1024,
    int height = 768,
  }) async* {
    final client = _clientFactory();
    try {
      final submit = await client.post(
        FluxApiConfig.submitEndpoint(model),
        headers: FluxApiConfig.headers(apiKey),
        body: jsonEncode({'prompt': prompt, 'width': width, 'height': height}),
      );
      if (submit.statusCode < 200 || submit.statusCode >= 300) {
        throw SseHttpException(submit.statusCode, submit.body);
      }
      final submitted =
          jsonDecode(utf8.decode(submit.bodyBytes)) as Map<String, dynamic>;
      final id = submitted['id'] as String?;
      final pollingUrl = submitted['polling_url'] as String?;
      if (id == null && pollingUrl == null) {
        yield const MessageError(
            'Flux did not return a job id — the API may have changed.');
        return;
      }
      final resultUri = pollingUrl != null
          ? Uri.parse(pollingUrl)
          : FluxApiConfig.resultEndpoint(id!);

      Uint8List? bytes;
      for (var attempt = 0; attempt < maxPolls; attempt++) {
        await Future<void>.delayed(pollInterval);
        final poll =
            await client.get(resultUri, headers: FluxApiConfig.headers(apiKey));
        if (poll.statusCode < 200 || poll.statusCode >= 300) {
          throw SseHttpException(poll.statusCode, poll.body);
        }
        final result =
            jsonDecode(utf8.decode(poll.bodyBytes)) as Map<String, dynamic>;
        final status = result['status'] as String?;
        if (status == 'Ready') {
          final sample =
              (result['result'] as Map<String, dynamic>?)?['sample'] as String?;
          if (sample == null) {
            yield const MessageError('Flux reported Ready but returned no image.');
            return;
          }
          final image = await client.get(Uri.parse(sample));
          if (image.statusCode < 200 || image.statusCode >= 300) {
            throw SseHttpException(image.statusCode, image.body);
          }
          bytes = image.bodyBytes;
          break;
        }
        if (status == 'Error' ||
            status == 'Failed' ||
            status == 'Content Moderated' ||
            status == 'Request Moderated') {
          yield MessageError('Flux could not generate this image ($status).');
          return;
        }
        // Pending / Task not found (eventual consistency) → keep polling.
      }

      if (bytes == null) {
        yield const MessageError(
            'Flux timed out before the image was ready — try again.');
        return;
      }
      yield ImageGenerated(pngBytes: bytes, alt: 'Generated image');
      yield const MessageComplete();
    } on SseHttpException catch (e) {
      yield MessageError('Flux API error ${e.statusCode}: ${e.body}');
    } catch (e) {
      yield MessageError('Could not reach api.bfl.ai — a network filter or '
          'CORS may be blocking browser-direct calls. ($e)');
    } finally {
      client.close();
    }
  }

  /// Cheap key check that does NOT spend a generation: probe the result
  /// endpoint with a throwaway id. A bad key is rejected (401/403); anything
  /// else (including a 404 "not found") means the key was accepted.
  @override
  Future<String?> validateKey(String apiKey) async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        FluxApiConfig.resultEndpoint('00000000-0000-0000-0000-000000000000'),
        headers: FluxApiConfig.headers(apiKey),
      );
      return switch (response.statusCode) {
        401 || 403 => 'That key was rejected (${response.statusCode}). Create '
            'one at dashboard.bfl.ai. Raw response: ${response.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        _ => null, // reachable + authorized (200/404/422 etc.)
      };
    } catch (e) {
      return 'Could not reach api.bfl.ai — a network filter or CORS may be '
          'blocking browser-direct calls. ($e)';
    } finally {
      client.close();
    }
  }
}
