import 'dart:convert';

import 'package:http/http.dart' as http;

import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'heygen_api_config.dart';
import 'provider_registry.dart';

/// The finished output of a Heygen job: the playable clip URL plus an optional
/// thumbnail (poster) URL.
class HeygenVideo {
  final String videoUrl;
  final String? thumbnailUrl;
  const HeygenVideo({required this.videoUrl, this.thumbnailUrl});
}

/// Raw-HTTP Heygen client. Avatar/video generation is asynchronous — submit →
/// poll status → read the finished `video_url` — so [generateAvatarVideo]
/// drives that loop. The app has no in-app video player, so the result is a
/// URL the UI links out to, not embedded bytes. Raw error bodies are surfaced
/// (Heygen browser-direct calls are CORS-risky).
class HeygenClient implements KeyValidatable {
  final http.Client Function() _clientFactory;
  final Duration pollInterval;
  final int maxPolls;

  HeygenClient({
    http.Client Function()? clientFactory,
    this.pollInterval = const Duration(seconds: 3),
    this.maxPolls = 100,
  }) : _clientFactory = clientFactory ?? createStreamingClient;

  /// Submits a talking-avatar job that speaks [script], polls until it is
  /// completed, and returns the finished video. Throws [SseHttpException] on a
  /// non-2xx response and [Exception] on failure/timeout.
  Future<HeygenVideo> generateAvatarVideo({
    required String apiKey,
    required String script,
    String avatarId = HeygenApiConfig.defaultAvatarId,
    String voiceId = HeygenApiConfig.defaultVoiceId,
  }) async {
    final client = _clientFactory();
    try {
      final submit = await client.post(
        HeygenApiConfig.generateEndpoint(),
        headers: HeygenApiConfig.headers(apiKey),
        body: jsonEncode({
          'video_inputs': [
            {
              'character': {
                'type': 'avatar',
                'avatar_id': avatarId,
                'avatar_style': 'normal',
              },
              'voice': {
                'type': 'text',
                'input_text': script,
                'voice_id': voiceId,
              },
            },
          ],
          'dimension': {'width': 1280, 'height': 720},
        }),
      );
      if (submit.statusCode < 200 || submit.statusCode >= 300) {
        throw SseHttpException(submit.statusCode, submit.body);
      }
      final submitted =
          jsonDecode(utf8.decode(submit.bodyBytes)) as Map<String, dynamic>;
      final videoId = (submitted['data'] as Map<String, dynamic>?)?['video_id']
          as String?;
      if (videoId == null) {
        throw Exception('Heygen did not return a video_id: ${submit.body}');
      }

      for (var attempt = 0; attempt < maxPolls; attempt++) {
        await Future<void>.delayed(pollInterval);
        final poll = await client.get(
          HeygenApiConfig.statusEndpoint(videoId),
          headers: HeygenApiConfig.headers(apiKey),
        );
        if (poll.statusCode < 200 || poll.statusCode >= 300) {
          throw SseHttpException(poll.statusCode, poll.body);
        }
        final data =
            (jsonDecode(utf8.decode(poll.bodyBytes)) as Map<String, dynamic>)[
                'data'] as Map<String, dynamic>?;
        final status = data?['status'] as String?;
        if (status == 'completed') {
          final url = data?['video_url'] as String?;
          if (url == null) {
            throw Exception('Heygen completed but returned no video_url.');
          }
          return HeygenVideo(
            videoUrl: url,
            thumbnailUrl: data?['thumbnail_url'] as String?,
          );
        }
        if (status == 'failed') {
          final error = data?['error'];
          throw Exception('Heygen job failed: ${error ?? 'unknown error'}');
        }
        // pending / processing / waiting → keep polling.
      }
      throw Exception('Heygen job did not finish in time.');
    } finally {
      client.close();
    }
  }

  /// Cheap key check: an authenticated GET of the avatar list. Returns null on
  /// success, else a human-readable problem (raw bodies included).
  @override
  Future<String?> validateKey(String apiKey) async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        HeygenApiConfig.avatarsEndpoint(),
        headers: HeygenApiConfig.headers(apiKey),
      );
      return switch (response.statusCode) {
        401 || 403 => 'That key was rejected (${response.statusCode}). Create '
            'one at app.heygen.com → Settings → API. Raw response: '
            '${response.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        >= 200 && < 300 => null,
        _ => 'API error ${response.statusCode}: ${response.body}',
      };
    } catch (e) {
      return 'Could not reach api.heygen.com — a network filter or CORS may be '
          'blocking browser-direct calls. ($e)';
    } finally {
      client.close();
    }
  }
}
