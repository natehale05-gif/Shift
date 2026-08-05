import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/providers/clients/openai_image_client.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/turn/chat_service.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  OpenAiImageClient client(http.Client Function() factory) =>
      OpenAiImageClient(clientFactory: factory);

  test('a base64 response becomes an image', () async {
    late Map<String, dynamic> sentBody;
    final mock = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.openai.com/v1/images/generations');
      expect(request.headers['authorization'], 'Bearer sk-test');
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(png)}
            ]
          }),
          200);
    });

    final events = await client(() => mock)
        .generateImage(access: const DirectKey('sk-test'), prompt: 'a pink flower')
        .toList();

    expect(sentBody['model'], OpenAiImageClient.defaultModel);
    expect(sentBody['prompt'], 'a pink flower');
    expect(sentBody.containsKey('response_format'), isFalse,
        reason: 'gpt-image-1 rejects the whole request over this parameter');
    final image = events.whereType<ImageGenerated>().single;
    expect(image.pngBytes, png);
    expect(events.last, isA<MessageComplete>());
  });

  test('a url response is fetched rather than dropped', () async {
    // gpt-image-1 always returns base64; the DALL·E models return a signed
    // URL. Handling only one shape would make a model swap silently produce
    // nothing at all.
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/images/generations')) {
        return http.Response(
            jsonEncode({
              'data': [
                {'url': 'https://delivery.openai.com/img.png'}
              ]
            }),
            200);
      }
      return http.Response.bytes(png, 200);
    });

    final events = await client(() => mock)
        .generateImage(access: const DirectKey('sk-test'), prompt: 'a pink flower')
        .toList();

    expect(events.whereType<ImageGenerated>().single.pngBytes, png);
  });

  test('an empty data array is an error, not a blank image', () async {
    final mock = MockClient(
        (_) async => http.Response(jsonEncode({'data': []}), 200));

    final events = await client(() => mock)
        .generateImage(access: const DirectKey('sk-test'), prompt: 'x')
        .toList();

    expect(events.whereType<ImageGenerated>(), isEmpty);
    expect(events.whereType<MessageError>(), hasLength(1));
  });

  test('403 names organization verification, which is the usual cause',
      () async {
    final mock = MockClient((_) async => http.Response('{"error":"denied"}', 403));

    final events = await client(() => mock)
        .generateImage(access: const DirectKey('sk-test'), prompt: 'x')
        .toList();

    final error = events.whereType<MessageError>().single;
    expect(error.message, contains('verified organization'));
  });

  test('429 says image generation bills separately from chat', () async {
    // A working chat key running out of image credit is otherwise baffling.
    final mock = MockClient((_) async => http.Response('{}', 429));

    final events = await client(() => mock)
        .generateImage(access: const DirectKey('sk-test'), prompt: 'x')
        .toList();

    expect(events.whereType<MessageError>().single.message,
        contains('bills separately'));
  });

  test('the endpoint tolerates a trailing slash on the base URL', () {
    expect(OpenAiImageClient.endpoint('https://api.openai.com/v1/').toString(),
        'https://api.openai.com/v1/images/generations');
    expect(OpenAiImageClient.endpoint('https://api.openai.com/v1').toString(),
        'https://api.openai.com/v1/images/generations');
  });

  test('only the DALL·E models are sent response_format', () {
    // Shipped once as "gpt-image-1 ignores it" — it does not. It answers
    // 400 Unknown parameter and no image is generated at all.
    expect(OpenAiImageClient.wantsResponseFormat('gpt-image-1'), isFalse);
    expect(OpenAiImageClient.wantsResponseFormat('dall-e-3'), isTrue);
    expect(OpenAiImageClient.wantsResponseFormat('dall-e-2'), isTrue);
    expect(
        OpenAiImageClient.buildRequestBody(prompt: 'x', model: 'dall-e-3')
            ['response_format'],
        'b64_json');
  });
}
