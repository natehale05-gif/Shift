import 'dart:convert';

import 'package:http/http.dart' as http;

import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'heygen_api_config.dart';
import 'provider_access.dart';
import 'provider_registry.dart';

/// A Heygen failure in words a user can act on.
///
/// Pure, and separate from the client, because the whole point is that this
/// text reaches the chat: a Heygen key that cannot render used to fall through
/// in silence to the simulated card, so "the Heygen API is not working" was
/// all anyone could tell.
String heygenProblem(int statusCode, String body) => switch (statusCode) {
      400 => 'Heygen rejected the request (400) — usually the avatar or voice '
          'is not available to this account. Raw response: $body',
      401 || 403 =>
        'Heygen rejected this key ($statusCode). Check it at app.heygen.com → '
            'Settings → API. Raw response: $body',
      402 => 'Heygen needs an active plan or credits before it will render '
          '(402). Raw response: $body',
      404 => 'Heygen has nothing at that endpoint (404) — the avatar id may '
          'have been retired. Raw response: $body',
      429 => 'Heygen rate-limited this key (429) — free plans allow very few '
          'renders. Raw response: $body',
      _ => 'Heygen API error $statusCode: $body',
    };

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
    required ProviderAccess access,
    required String script,
    String? avatarId,
    String? voiceId,
  }) async {
    final client = _clientFactory();
    try {
      // Ask the account which avatar and voice it can use, rather than sending
      // ids picked at build time. Heygen retires stock avatars, so a constant
      // that worked once starts failing at submit for everyone.
      avatarId ??= await _firstId(client, access, HeygenApiConfig.avatarsEndpoint,
              '/v2/avatars',
              const ['avatars', 'talking_photos'], const ['avatar_id', 'talking_photo_id']) ??
          HeygenApiConfig.fallbackAvatarId;
      voiceId ??= await _firstId(client, access, HeygenApiConfig.voicesEndpoint,
              '/v2/voices',
              const ['voices'], const ['voice_id']) ??
          HeygenApiConfig.fallbackVoiceId;

      final generate = routeCall(
        access,
        direct: (_) => HeygenApiConfig.generateEndpoint(),
        directHeaders: HeygenApiConfig.headers,
        path: '/v2/video/generate',
      );
      final submit = await client.post(
        generate.uri,
        headers: generate.headers,
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
        // Polling is a GET, and it is why the proxy had to learn a second
        // method: it could submit a render and never collect it.
        final statusCall = routeCall(
          access,
          direct: (_) => HeygenApiConfig.statusEndpoint(videoId),
          directHeaders: HeygenApiConfig.headers,
          path: '/v1/video_status.get',
          query: {'video_id': videoId},
        );
        final poll =
            await client.get(statusCall.uri, headers: statusCall.headers);
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

  /// The first id under any of [listKeys] in a v2 listing, or null if the
  /// call fails or lists nothing — in which case the caller uses its fallback
  /// rather than giving up, since a listing that cannot be read is not proof
  /// that generation would fail.
  ///
  /// Several shapes are accepted because Heygen's listings differ: avatars
  /// come back under `avatars` and `talking_photos` with different id fields.
  Future<String?> _firstId(
    http.Client client,
    ProviderAccess access,
    Uri Function() endpoint,
    String path,
    List<String> listKeys,
    List<String> idKeys,
  ) async {
    try {
      final route = routeCall(
        access,
        direct: (_) => endpoint(),
        directHeaders: HeygenApiConfig.headers,
        path: path,
      );
      final response = await client.get(route.uri, headers: route.headers);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final data = payload['data'];
      for (final listKey in listKeys) {
        final list = data is Map ? data[listKey] : null;
        if (list is! List) continue;
        for (final entry in list) {
          if (entry is! Map) continue;
          for (final idKey in idKeys) {
            final id = entry[idKey];
            if (id is String && id.isNotEmpty) return id;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
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
