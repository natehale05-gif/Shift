import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/providers/clients/heygen_api_config.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/providers/clients/heygen_client.dart';

void main() {
  HeygenClient client(http.Client Function() factory) => HeygenClient(
        clientFactory: factory,
        pollInterval: Duration.zero,
        maxPolls: 10,
      );

  test('discovers an avatar and voice, submits, polls, returns the url',
      () async {
    // The ids used to be constants picked at build time. Heygen retires stock
    // avatars, so those started being rejected at submit for everyone — and
    // the failure was swallowed, which is why "Heygen is not working" was all
    // anyone could report. The account's own listings are asked first now.
    var polls = 0;
    Map<String, dynamic>? submitted;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.headers['x-api-key'], 'hg-key');
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'data': {'video_id': 'v-1'}}), 200);
      }
      if (request.url.path.endsWith('/v2/avatars')) {
        return http.Response(
            jsonEncode({
              'data': {
                'avatars': [
                  {'avatar_id': 'acct-avatar-1'}
                ]
              }
            }),
            200);
      }
      if (request.url.path.endsWith('/v2/voices')) {
        return http.Response(
            jsonEncode({
              'data': {
                'voices': [
                  {'voice_id': 'acct-voice-1'}
                ]
              }
            }),
            200);
      }
      polls++;
      if (polls < 2) {
        return http.Response(jsonEncode({'data': {'status': 'processing'}}), 200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'status': 'completed',
              'video_url': 'https://cdn.heygen/v-1.mp4',
              'thumbnail_url': 'https://cdn.heygen/v-1.jpg',
            }
          }),
          200);
    });

    final video = await client(() => mock)
        .generateAvatarVideo(access: const DirectKey('hg-key'), script: 'Hello world');

    final input = (submitted!['video_inputs'] as List).first as Map;
    expect(input['voice']['input_text'], 'Hello world');
    expect(input['character']['avatar_id'], 'acct-avatar-1');
    expect(input['voice']['voice_id'], 'acct-voice-1');
    expect(video.videoUrl, 'https://cdn.heygen/v-1.mp4');
    expect(video.thumbnailUrl, 'https://cdn.heygen/v-1.jpg');
    expect(polls, 2);
  });

  test('an unreadable listing falls back rather than giving up', () async {
    // A listing that 403s is not proof that generation would fail, so the
    // constants remain as a last resort.
    Map<String, dynamic>? submitted;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'data': {'video_id': 'v'}}), 200);
      }
      if (request.url.path.startsWith('/v2/')) {
        return http.Response('{}', 403);
      }
      return http.Response(
          jsonEncode({
            'data': {'status': 'completed', 'video_url': 'https://cdn/v.mp4'}
          }),
          200);
    });

    await client(() => mock)
        .generateAvatarVideo(access: const DirectKey('k'), script: 'Hi');

    final input = (submitted!['video_inputs'] as List).first as Map;
    expect(input['character']['avatar_id'], HeygenApiConfig.fallbackAvatarId);
    expect(input['voice']['voice_id'], HeygenApiConfig.fallbackVoiceId);
  });

  test('an explicit avatar id skips discovery entirely', () async {
    var listings = 0;
    Map<String, dynamic>? submitted;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'data': {'video_id': 'v'}}), 200);
      }
      if (request.url.path.startsWith('/v2/')) {
        listings++;
        return http.Response('{}', 200);
      }
      return http.Response(
          jsonEncode({
            'data': {'status': 'completed', 'video_url': 'https://cdn/v.mp4'}
          }),
          200);
    });

    await client(() => mock).generateAvatarVideo(
        access: const DirectKey('k'), script: 'Hi', avatarId: 'mine', voiceId: 'my-voice');

    expect(listings, 0, reason: 'no reason to ask when the caller decided');
    final input = (submitted!['video_inputs'] as List).first as Map;
    expect(input['character']['avatar_id'], 'mine');
  });

  test('a failed job throws', () async {
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(jsonEncode({'data': {'video_id': 'v'}}), 200);
      }
      return http.Response(
          jsonEncode({'data': {'status': 'failed', 'error': 'bad avatar'}}), 200);
    });
    expect(
      () => client(() => mock).generateAvatarVideo(access: const DirectKey('k'), script: 's'),
      throwsA(isA<Exception>()),
    );
  });

  group('validateKey', () {
    test('a 200 avatar list means the key is accepted', () async {
      final mock = MockClient((_) async => http.Response('{"data":[]}', 200));
      expect(await client(() => mock).validateKey('good'), isNull);
    });

    test('401 is a rejection with the raw body', () async {
      final mock = MockClient((_) async => http.Response('{"message":"nope"}', 401));
      final problem = await client(() => mock).validateKey('bad');
      expect(problem, contains('401'));
      expect(problem, contains('nope'));
    });
  });
}
