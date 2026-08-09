import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../turn/job_output.dart';
import '../../turn/turn_event.dart';
import '../access.dart';

/// Generating an image with Gemini.
///
/// Not streamed: this endpoint answers once, with the picture inline as base64
/// in a `parts` array. Details carried from v1 and reviewed rather than
/// reinvented:
///
/// * `responseModalities: ['TEXT', 'IMAGE']` is required, or the model
///   describes the picture instead of drawing it — a reply that looks like
///   success and contains no image.
/// * A direct call puts the key in the URL, which is Gemini's own scheme. A
///   managed call must not, or the key ends up in proxy and CDN logs; the
///   proxy attaches `x-goog-api-key` server-side instead.
/// * The model can legitimately answer with text and no image — a refusal, or
///   a prompt it will not draw. That is a failed step with a reason, not an
///   empty success.
class GeminiImage {
  static const model = 'gemini-2.5-flash-image';

  final http.Client Function() _clientFactory;

  GeminiImage({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static ({Uri uri, Map<String, String> headers}) _target(
    ProviderAccess access,
  ) =>
      switch (access) {
        DirectKey(:final key) => (
            uri: Uri.parse('https://generativelanguage.googleapis.com/v1beta/'
                'models/$model:generateContent?key=$key'),
            headers: const {'content-type': 'application/json'},
          ),
        ManagedAccess(:final base, :final headers) => (
            uri: base.replace(
              path: '${base.path}/v1beta/models/$model:generateContent',
            ),
            headers: {'content-type': 'application/json', ...headers},
          ),
      };

  static Map<String, dynamic> buildBody(String prompt) => {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
        },
      };

  Stream<TurnEvent> generate({
    required String stepId,
    required ProviderAccess access,
    required String prompt,
  }) async* {
    final target = _target(access);
    final client = _clientFactory();

    http.Response response;
    try {
      response = await client.post(
        target.uri,
        headers: target.headers,
        body: jsonEncode(buildBody(prompt)),
      );
    } catch (_) {
      yield StepFailed(stepId, reason: 'Could not reach the image provider.');
      return;
    } finally {
      client.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      yield StepFailed(stepId, reason: _readable(response.statusCode));
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      yield StepFailed(stepId, reason: 'The image provider sent something '
          'unreadable.');
      return;
    }

    final image = extractImage(payload);
    if (image == null) {
      // Text and no picture is a real answer — usually a refusal. Reporting it
      // as a provider fault would send the user to retry something that will
      // never work; reporting success with nothing to show is worse.
      yield StepFailed(
        stepId,
        reason: 'The model did not produce an image for that prompt. '
            'Rewording it usually helps.',
      );
      return;
    }

    yield StepCompleted(
      stepId,
      ImageOutput(bytes: image, mimeType: 'image/png', prompt: prompt),
    );
  }

  /// Pulls the first inline image out of a response. Static and pure, so the
  /// shape can be pinned against recorded payloads without any HTTP.
  static Uint8List? extractImage(Map<String, dynamic> payload) {
    final candidates = payload['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) return null;

    final parts = ((candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>?)?['parts'] as List<dynamic>? ??
        const [];

    for (final part in parts) {
      // Both spellings appear in the wild depending on endpoint and version,
      // and accepting only one is a silent "no image" on a response that
      // plainly contains one.
      final inline = (part as Map<String, dynamic>)['inlineData'] ??
          part['inline_data'];
      final data = (inline as Map<String, dynamic>?)?['data'] as String?;
      if (data == null || data.isEmpty) continue;
      try {
        return base64Decode(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _readable(int status) => switch (status) {
        400 => 'The image provider rejected that request.',
        401 || 403 => 'That key was rejected by the image provider.',
        429 => 'The image provider is rate limiting; try again shortly.',
        _ => 'The image provider could not complete that step.',
      };
}
