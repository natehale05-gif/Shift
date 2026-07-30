import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'provider_registry.dart';

/// ElevenLabs text-to-speech.
///
/// Returns raw audio bytes rather than a [ChatEvent] stream: unlike image
/// generation there is no incremental event to emit, and the caller needs the
/// bytes themselves to attach to the voice result. Failures throw, so the
/// caller can fall back to the local synthesizer and still deliver something
/// playable.
class ElevenLabsClient implements KeyValidatable {
  final http.Client Function() _clientFactory;

  ElevenLabsClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

  static const base = 'https://api.elevenlabs.io/v1';

  /// "Rachel" — ElevenLabs' default stock voice, available on every account,
  /// so a fresh key works without the user first picking a voice.
  static const defaultVoiceId = '21m00Tcm4TlvDq8ikWAM';
  static const defaultModel = 'eleven_multilingual_v2';

  /// PCM rather than MP3: everything downstream — the card's player, the
  /// download, the off-web file handoff — speaks WAV, and raw PCM becomes WAV
  /// by prepending a header. Taking MP3 would mean shipping a decoder.
  static const outputFormat = 'pcm_44100';
  static const sampleRate = 44100;

  static Uri endpoint(String voiceId) => Uri.parse(
      '$base/text-to-speech/$voiceId?output_format=$outputFormat');

  /// ElevenLabs uses its own header, not Bearer.
  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'xi-api-key': apiKey,
      };

  /// Speaks [text] and returns raw 16-bit mono PCM at [sampleRate]. Throws
  /// [SseHttpException] on an API error so the caller can decide whether to
  /// fall back to the local synthesizer.
  Future<Uint8List> speak({
    required String apiKey,
    required String text,
    String voiceId = defaultVoiceId,
    String model = defaultModel,
  }) async {
    final client = _clientFactory();
    try {
      final response = await client.post(
        endpoint(voiceId),
        headers: headers(apiKey),
        body: jsonEncode({'text': text, 'model_id': model}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SseHttpException(response.statusCode, response.body);
      }
      return Uint8List.fromList(response.bodyBytes);
    } finally {
      client.close();
    }
  }

  /// Lists the account's voices — cheap, and it spends no characters from the
  /// quota, unlike synthesizing a test phrase would.
  @override
  Future<String?> validateKey(String apiKey) async {
    final client = _clientFactory();
    try {
      final response =
          await client.get(Uri.parse('$base/voices'), headers: headers(apiKey));
      return switch (response.statusCode) {
        200 => null,
        401 || 403 => 'ElevenLabs rejected this key '
            '(${response.statusCode}). Find it at elevenlabs.io → your '
            'profile → API key. Raw response: ${response.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        _ => 'ElevenLabs API error ${response.statusCode}: ${response.body}',
      };
    } catch (e) {
      return 'Could not reach api.elevenlabs.io — a network filter or CORS '
          'may be blocking browser-direct calls. ($e)';
    } finally {
      client.close();
    }
  }
}
