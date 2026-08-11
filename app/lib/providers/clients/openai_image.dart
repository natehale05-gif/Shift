import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../turn/job_output.dart';
import '../../turn/turn_event.dart';
import '../access.dart';
import '../failure_text.dart';
import '../streaming/reachability.dart';
import '../streaming/sse_client.dart' show createProviderHttpClient;

/// Talking to OpenAI's image endpoint.
///
/// **Not SSE, and that is the whole shape of this file.** Images come back as
/// one JSON body when the picture is finished, so there is no stream to fold
/// and no [statusAware] to lean on — the status arrives on the response and is
/// read directly. Everything else in `clients/` streams; this one does not, and
/// pretending otherwise would mean inventing progress it cannot report.
///
/// Two wire details that are easy to get wrong:
///
/// * **`gpt-image-1` always returns base64**, never a URL, and it does not
///   accept `response_format` at all — sending it is a 400. The older models
///   default to a URL that expires, so a client written against those and
///   pointed at this one silently gets no bytes.
/// * **The sizes are a fixed set.** An arbitrary aspect ratio is a 400, so the
///   requested shape is mapped to the nearest one the endpoint accepts rather
///   than passed through.
class OpenAiImage {
  static const _path = '/images/generations';

  final http.Client Function() _clientFactory;
  final Future<Reach> Function() _reach;

  OpenAiImage({
    http.Client Function()? clientFactory,
    Future<Reach> Function()? reach,
  })  : _clientFactory = clientFactory ?? createProviderHttpClient,
        _reach = reach ?? probeReach;

  static Uri endpoint(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$_path');
  }

  static ({Uri uri, Map<String, String> headers}) target(
    ProviderAccess access,
    String baseUrl,
  ) =>
      switch (access) {
        DirectKey(:final key) => (
            uri: endpoint(baseUrl),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $key',
            },
          ),
        ManagedAccess(:final base, :final headers) => (
            uri: base.replace(path: '${base.path}$_path'),
            headers: {'content-type': 'application/json', ...headers},
          ),
      };

  /// What the endpoint accepts, and nothing else.
  ///
  /// The planner speaks in aspect ratios because that is what people ask for;
  /// this is where a ratio becomes one of three sizes. Anything unrecognised
  /// becomes the square, which is the shape a request that said nothing about
  /// shape wanted anyway.
  static String sizeFor(String? aspectRatio) => switch (aspectRatio) {
        '16:9' || '3:2' || '21:9' || '4:3' || '5:4' => '1536x1024',
        '9:16' || '2:3' || '3:4' || '4:5' => '1024x1536',
        _ => '1024x1024',
      };

  static Map<String, dynamic> buildBody({
    required String model,
    required String prompt,
    String? aspectRatio,
  }) =>
      {
        'model': model,
        'prompt': prompt,
        'n': 1,
        'size': sizeFor(aspectRatio),
        // No `response_format`: gpt-image-1 rejects it and returns base64
        // regardless, which is what this client wants.
      };

  Stream<TurnEvent> generate({
    required String stepId,
    required ProviderAccess access,
    required String model,
    required String baseUrl,
    required String prompt,
    String? aspectRatio,
    String? blocked,
  }) async* {
    final resolved = target(access, baseUrl);
    final client = _clientFactory();

    // Said before the wait rather than after it. A picture takes tens of
    // seconds and reports nothing while it does, so without this the turn looks
    // stalled for its whole duration.
    yield StepProgress(stepId, note: 'Drawing');

    try {
      final response = await client.post(
        resolved.uri,
        headers: resolved.headers,
        body: jsonEncode(buildBody(
          model: model,
          prompt: prompt,
          aspectRatio: aspectRatio,
        )),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        yield StepFailed(
          stepId,
          reason: sentenceForStatus(response.statusCode),
          detail: 'HTTP ${response.statusCode} from ${resolved.uri.host}',
        );
        return;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['data'] as List<dynamic>? ?? const [];
      final encoded = data.isEmpty
          ? null
          : (data.first as Map<String, dynamic>)['b64_json'] as String?;

      if (encoded == null || encoded.isEmpty) {
        // A 200 with no bytes. Named separately from a failed request because
        // the fix is different and because "it worked but there is no picture"
        // is otherwise reported as success with nothing on screen.
        yield StepFailed(
          stepId,
          reason: 'The provider answered without a picture.',
          detail: 'no b64_json in the response from ${resolved.uri.host}',
        );
        return;
      }

      yield StepCompleted(
        stepId,
        ImageOutput(
          bytes: Uint8List.fromList(base64Decode(encoded)),
          mimeType: 'image/png',
          prompt: prompt,
        ),
      );
    } catch (error) {
      // No status at all. Same three-way question the streaming clients ask,
      // and the same answer, so a blocked browser request does not read as an
      // outage here and as a shield there.
      final where = await _reach();
      yield StepFailed(
        stepId,
        reason: where == Reach.up && blocked != null
            ? blocked
            : sentenceForUnreachable(where),
        detail: '$error · ${resolved.uri.host}',
      );
    } finally {
      client.close();
    }
  }
}
