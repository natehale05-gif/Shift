/// Heygen endpoints and defaults. Heygen's avatar/video generation is
/// asynchronous: POST a generate request, then poll status until the finished
/// `video_url` (and a thumbnail) are ready.
class HeygenApiConfig {
  HeygenApiConfig._();

  static const base = 'https://api.heygen.com';

  /// v2 video generation.
  static Uri generateEndpoint() => Uri.parse('$base/v2/video/generate');

  /// v1 status polling for a submitted video id.
  static Uri statusEndpoint(String videoId) =>
      Uri.parse('$base/v1/video_status.get?video_id=$videoId');

  /// v2 avatar listing — a cheap authenticated GET used for key validation
  /// and to discover an avatar this account can actually use.
  static Uri avatarsEndpoint() => Uri.parse('$base/v2/avatars');

  /// v2 voice listing, for the same reason.
  static Uri voicesEndpoint() => Uri.parse('$base/v2/voices');

  /// Last-resort ids, used only when the account lists nothing.
  ///
  /// These were the *only* ids the client ever sent, which is why avatar jobs
  /// failed: Heygen retires stock avatars, and a retired id is rejected at
  /// submit. The ids a key can actually use are the ones its own account
  /// lists, so those are asked for first.
  static const fallbackAvatarId = 'Daisy-inskirt-20220818';
  static const fallbackVoiceId = '2d5b0e6cf36f460aa7fc47e3eee4ba54';

  static const model = 'heygen-avatar';

  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-api-key': apiKey,
      };
}
