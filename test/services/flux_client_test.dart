import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/providers/flux_client.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  FluxClient client(http.Client Function() factory) => FluxClient(
        clientFactory: factory,
        pollInterval: Duration.zero,
        maxPolls: 10,
      );

  test('submit → poll (Pending then Ready) → fetch yields an image', () async {
    var polls = 0;
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.headers['x-key'], 'flux-key');
        return http.Response(
            jsonEncode({'id': 'job-1', 'polling_url': 'https://poll/job-1'}),
            200);
      }
      if (request.url.toString() == 'https://poll/job-1') {
        polls++;
        if (polls < 2) return http.Response(jsonEncode({'status': 'Pending'}), 200);
        return http.Response(
            jsonEncode({
              'status': 'Ready',
              'result': {'sample': 'https://delivery/img.png'}
            }),
            200);
      }
      // The signed sample URL → raw bytes.
      return http.Response.bytes(png, 200);
    });

    final events =
        await client(() => mock).generateImage(apiKey: 'flux-key', prompt: 'a fox').toList();

    final image = events.whereType<ImageGenerated>().single;
    expect(image.pngBytes, png);
    expect(events.last, isA<MessageComplete>());
    expect(polls, 2);
  });

  test('a moderated result surfaces an error, not an image', () async {
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(jsonEncode({'id': 'x', 'polling_url': 'https://poll/x'}), 200);
      }
      return http.Response(jsonEncode({'status': 'Content Moderated'}), 200);
    });
    final events =
        await client(() => mock).generateImage(apiKey: 'k', prompt: 'p').toList();
    expect(events.whereType<ImageGenerated>(), isEmpty);
    expect(events.whereType<MessageError>(), hasLength(1));
  });

  test('a 401 on submit surfaces the raw error body', () async {
    final mock = MockClient((request) async =>
        http.Response('{"detail":"bad key"}', 401));
    final events =
        await client(() => mock).generateImage(apiKey: 'nope', prompt: 'p').toList();
    final error = events.whereType<MessageError>().single;
    expect(error.message, contains('401'));
    expect(error.message, contains('bad key'));
  });

  group('validateKey', () {
    test('401/403 is a rejection', () async {
      final mock = MockClient((_) async => http.Response('{"detail":"no"}', 401));
      expect(await client(() => mock).validateKey('bad'), contains('401'));
    });

    test('a 404 (unknown job) means the key was accepted', () async {
      final mock = MockClient((_) async => http.Response('{"detail":"not found"}', 404));
      expect(await client(() => mock).validateKey('good'), isNull);
    });
  });
}
