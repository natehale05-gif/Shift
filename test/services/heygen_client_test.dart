import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/providers/clients/heygen_client.dart';

void main() {
  HeygenClient client(http.Client Function() factory) => HeygenClient(
        clientFactory: factory,
        pollInterval: Duration.zero,
        maxPolls: 10,
      );

  test('submit → poll (processing then completed) → returns the video url',
      () async {
    var polls = 0;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.headers['x-api-key'], 'hg-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(((body['video_inputs'] as List).first as Map)['voice']['input_text'],
            'Hello world');
        return http.Response(jsonEncode({'data': {'video_id': 'v-1'}}), 200);
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
        .generateAvatarVideo(apiKey: 'hg-key', script: 'Hello world');
    expect(video.videoUrl, 'https://cdn.heygen/v-1.mp4');
    expect(video.thumbnailUrl, 'https://cdn.heygen/v-1.jpg');
    expect(polls, 2);
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
      () => client(() => mock).generateAvatarVideo(apiKey: 'k', script: 's'),
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
