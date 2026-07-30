import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../streaming/sse_client.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';

/// Where a video job has got to.
enum VideoJobStatus { queued, inProgress, completed, failed }

/// One poll of a video job.
class VideoJob {
  final String id;
  final VideoJobStatus status;

  /// 0–100 when the provider reports it, else null.
  final int? progress;

  /// The provider's own message when [status] is [VideoJobStatus.failed].
  final String? error;

  const VideoJob({
    required this.id,
    required this.status,
    this.progress,
    this.error,
  });

  bool get done =>
      status == VideoJobStatus.completed || status == VideoJobStatus.failed;
}

/// Reads a job object out of a create/poll response.
///
/// Deliberately forgiving about the status spelling. Providers report the same
/// four states under several names (`in_progress`, `processing`, `running`,
/// `succeeded`, `completed`), and a status this does not recognise is treated
/// as still-running rather than as failure — a job wrongly called failed loses
/// work that was actually finishing.
VideoJob parseVideoJob(Map<String, dynamic> json) {
  final raw = (json['status'] as String? ?? '').toLowerCase();
  final status = switch (raw) {
    'completed' || 'succeeded' || 'success' => VideoJobStatus.completed,
    'failed' || 'error' || 'cancelled' || 'canceled' => VideoJobStatus.failed,
    'queued' || 'pending' || 'created' => VideoJobStatus.queued,
    _ => VideoJobStatus.inProgress,
  };
  final error = json['error'];
  return VideoJob(
    id: json['id'] as String? ?? '',
    status: status,
    progress: (json['progress'] as num?)?.round(),
    error: error is Map ? error['message'] as String? : error as String?,
  );
}

/// A readable reason a video render failed, from the status alone.
///
/// Same shape as `heygenProblem` and `elevenLabsProblem`: the user should
/// learn whether it was the key, the plan or the request, rather than being
/// handed a simulated card in silence.
String openAiVideoProblem(int statusCode, String body) => switch (statusCode) {
      401 || 403 => 'OpenAI rejected the key for video, so this is a simulated '
          'clip. Check it in Settings — video needs an account with Sora '
          'access.',
      404 => 'This OpenAI account does not have the video model enabled, so '
          'this is a simulated clip.',
      429 => 'OpenAI is rate-limiting video or the quota is used up, so this '
          'is a simulated clip.',
      _ => 'OpenAI returned $statusCode for the video, so this is a simulated '
          'clip.',
    };

/// Text-to-video on OpenAI.
///
/// **Verification boundary, stated rather than glossed:** this environment has
/// no OpenAI key and the API reference is unreachable from it, so the wire
/// shape below is written from the documented Sora endpoints and proven only
/// against a fake client. If a real render fails, this file is the first place
/// to look, and [openAiVideoProblem] surfaces the status so it is diagnosable
/// rather than silent. Everything downstream of it — routing, the card, the
/// asset store — is covered by tests.
class OpenAiVideoClient {
  final http.Client Function() _clientFactory;

  OpenAiVideoClient({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? createStreamingClient;

  static const base = 'https://api.openai.com/v1';
  static const defaultModel = 'sora-2';

  /// How long to wait for a render before giving up. Sora takes minutes for a
  /// few seconds of video, so this is generous — but bounded, because a job
  /// that never finishes must not hold the turn open forever.
  static const pollTimeout = Duration(minutes: 8);
  static const pollInterval = Duration(seconds: 5);

  /// Starts a render and returns the job.
  Future<VideoJob> start({
    required String apiKey,
    required String prompt,
    String model = defaultModel,
    int seconds = 4,
    String size = '1280x720',
  }) async {
    final client = _clientFactory();
    try {
      final response = await client.post(
        Uri.parse('$base/videos'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'prompt': prompt,
          'seconds': '$seconds',
          'size': size,
        }),
      );
      if (response.statusCode >= 400) {
        throw SseHttpException(response.statusCode, response.body);
      }
      return parseVideoJob(jsonDecode(response.body) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  Future<VideoJob> poll({
    required String apiKey,
    required String id,
  }) async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        Uri.parse('$base/videos/$id'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode >= 400) {
        throw SseHttpException(response.statusCode, response.body);
      }
      return parseVideoJob(jsonDecode(response.body) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  /// The finished mp4.
  ///
  /// Downloaded rather than linked: the content endpoint needs the API key, so
  /// a bare URL in a `<video src>` would 401. The bytes go to the asset store
  /// like generated images and audio already do.
  Future<Uint8List> download({
    required String apiKey,
    required String id,
  }) async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        Uri.parse('$base/videos/$id/content'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode >= 400) {
        throw SseHttpException(response.statusCode, response.body);
      }
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  /// Start, wait, download — the whole render as one call.
  Future<Uint8List> render({
    required String apiKey,
    required String prompt,
    String model = defaultModel,
    int seconds = 4,
    String size = '1280x720',
    void Function(VideoJob job)? onProgress,
  }) async {
    var job = await start(
      apiKey: apiKey,
      prompt: prompt,
      model: model,
      seconds: seconds,
      size: size,
    );
    onProgress?.call(job);

    final deadline = DateTime.now().add(pollTimeout);
    while (!job.done) {
      if (DateTime.now().isAfter(deadline)) {
        throw SseHttpException(
            504, 'The video was still rendering after ${pollTimeout.inMinutes} '
                'minutes.');
      }
      await Future<void>.delayed(pollInterval);
      job = await poll(apiKey: apiKey, id: job.id);
      onProgress?.call(job);
    }
    if (job.status == VideoJobStatus.failed) {
      throw SseHttpException(422, job.error ?? 'The render failed.');
    }
    return download(apiKey: apiKey, id: job.id);
  }
}
