import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/features/studios/media/audio_synth_service.dart';
import 'package:shift_ai/providers/clients/elevenlabs_client.dart';
import 'package:shift_ai/providers/clients/fal_client.dart';
import 'package:shift_ai/providers/clients/replicate_client.dart';
import 'package:shift_ai/turn/chat_service.dart';

final _png = Uint8List.fromList([137, 80, 78, 71, 5, 5, 5]);

void main() {
  group('fal', () {
    test('one POST returns the image — no polling', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (request.url.toString() == 'https://fal.run/fal-ai/flux/schnell') {
          expect(request.headers['authorization'], 'Key fal-key',
              reason: 'fal uses Key, not Bearer');
          return http.Response(
              jsonEncode({
                'images': [
                  {'url': 'https://cdn.fal/img.png'}
                ]
              }),
              200);
        }
        return http.Response.bytes(_png, 200);
      });

      final events = await FalClient(clientFactory: () => mock)
          .generateImage(apiKey: 'fal-key', prompt: 'a pink flower')
          .toList();

      expect(events.whereType<ImageGenerated>().single.pngBytes, _png);
      expect(calls, 2, reason: 'generate then fetch, nothing else');
    });

    test('the single-image response shape works too', () async {
      final mock = MockClient((request) async {
        if (request.url.host == 'fal.run') {
          return http.Response(
              jsonEncode({
                'image': {'url': 'https://cdn.fal/img.png'}
              }),
              200);
        }
        return http.Response.bytes(_png, 200);
      });

      final events = await FalClient(clientFactory: () => mock)
          .generateImage(apiKey: 'k', prompt: 'x')
          .toList();
      expect(events.whereType<ImageGenerated>(), hasLength(1));
    });

    test('a rejected key is reported, not swallowed', () async {
      final mock = MockClient((_) async => http.Response('{"detail":"no"}', 401));
      final events = await FalClient(clientFactory: () => mock)
          .generateImage(apiKey: 'bad', prompt: 'x')
          .toList();
      expect(events.whereType<MessageError>().single.message, contains('401'));
    });

    test('validateKey accepts a 422 — authorized, just no prompt', () async {
      // Generating a throwaway image to test a key would spend real credit to
      // answer a question the status code already answers.
      final mock = MockClient((_) async => http.Response('{"detail":[]}', 422));
      expect(await FalClient(clientFactory: () => mock).validateKey('k'), isNull);

      final bad = MockClient((_) async => http.Response('{}', 403));
      expect(await FalClient(clientFactory: () => bad).validateKey('k'),
          contains('403'));
    });
  });

  group('replicate', () {
    ReplicateClient client(http.Client Function() f) =>
        ReplicateClient(clientFactory: f, pollInterval: Duration.zero);

    test('Prefer: wait returns a finished prediction in one round trip',
        () async {
      var polls = 0;
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.headers['prefer'], 'wait');
          return http.Response(
              jsonEncode({
                'status': 'succeeded',
                'output': ['https://replicate.delivery/img.png']
              }),
              201);
        }
        if (request.url.host == 'replicate.delivery') {
          return http.Response.bytes(_png, 200);
        }
        polls++;
        return http.Response('{}', 200);
      });

      final events = await client(() => mock)
          .generateImage(apiKey: 'r8_key', prompt: 'x')
          .toList();

      expect(events.whereType<ImageGenerated>().single.pngBytes, _png);
      expect(polls, 0, reason: 'nothing to poll when wait succeeded');
    });

    test('an unfinished prediction is polled until it succeeds', () async {
      var polls = 0;
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
              jsonEncode({
                'status': 'processing',
                'urls': {'get': 'https://api.replicate.com/v1/predictions/p1'}
              }),
              201);
        }
        if (request.url.toString().endsWith('/predictions/p1')) {
          polls++;
          if (polls < 3) {
            return http.Response(
                jsonEncode({
                  'status': 'processing',
                  'urls': {'get': 'https://api.replicate.com/v1/predictions/p1'}
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'status': 'succeeded',
                'output': 'https://replicate.delivery/img.png'
              }),
              200);
        }
        return http.Response.bytes(_png, 200);
      });

      final events = await client(() => mock)
          .generateImage(apiKey: 'k', prompt: 'x')
          .toList();

      expect(events.whereType<ImageGenerated>().single.pngBytes, _png,
          reason: 'a bare-string output is read as well as a list');
      expect(polls, 3);
    });

    test('a failed prediction reports why rather than timing out', () async {
      final mock = MockClient((_) async => http.Response(
          jsonEncode({'status': 'failed', 'error': 'NSFW filter'}), 201));

      final events = await client(() => mock)
          .generateImage(apiKey: 'k', prompt: 'x')
          .toList();

      expect(events.whereType<MessageError>().single.message,
          contains('NSFW filter'));
    });

    test('402 names billing, which is what it actually means', () async {
      final mock = MockClient((_) async => http.Response('{}', 402));
      final events = await client(() => mock)
          .generateImage(apiKey: 'k', prompt: 'x')
          .toList();
      expect(events.whereType<MessageError>().single.message,
          contains('billing'));
    });
  });

  group('elevenlabs', () {
    test('speaks and returns PCM the WAV path can wrap', () async {
      final pcm = Uint8List.fromList(List.generate(64, (i) => i));
      late Map<String, dynamic> body;
      final mock = MockClient((request) async {
        expect(request.headers['xi-api-key'], 'sk_voice');
        expect(request.url.queryParameters['output_format'],
            ElevenLabsClient.outputFormat);
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(pcm, 200);
      });

      final spoken = await ElevenLabsClient(clientFactory: () => mock)
          .speak(apiKey: 'sk_voice', text: 'Hello there');

      expect(body['text'], 'Hello there');
      expect(spoken, pcm);

      // The header is what makes provider audio playable by the existing card.
      final wav = AudioSynthService.wavFromPcm16(spoken,
          sampleRate: ElevenLabsClient.sampleRate);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(wav.length, pcm.length + 44);
    });

    test('an API error throws so the caller can fall back', () async {
      final mock = MockClient((_) async => http.Response('nope', 401));
      expect(
          () => ElevenLabsClient(clientFactory: () => mock)
              .speak(apiKey: 'bad', text: 'x'),
          throwsA(anything));
    });

    test('validateKey lists voices rather than spending characters', () async {
      final mock = MockClient((request) async {
        expect(request.url.toString(), endsWith('/voices'));
        expect(request.method, 'GET');
        return http.Response('{"voices":[]}', 200);
      });
      expect(
          await ElevenLabsClient(clientFactory: () => mock).validateKey('k'),
          isNull);
    });

    test('a rejected key says where to find the right one', () async {
      final mock = MockClient((_) async => http.Response('{}', 401));
      expect(await ElevenLabsClient(clientFactory: () => mock).validateKey('k'),
          contains('elevenlabs.io'));
    });
  });
}
