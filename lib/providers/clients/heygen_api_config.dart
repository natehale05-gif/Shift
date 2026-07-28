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

  /// v2 avatar listing — a cheap authenticated GET used for key validation.
  static Uri avatarsEndpoint() => Uri.parse('$base/v2/avatars');

  /// A default stock avatar / voice so a talking-avatar job can be submitted
  /// from just a script. Users with their own avatars can extend this later.
  static const defaultAvatarId = 'Daisy-inskirt-20220818';
  static const defaultVoiceId = '2d5b0e6cf36f460aa7fc47e3eee4ba54';

  static const model = 'heygen-avatar';

  static Map<String, String> headers(String apiKey) => {
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-api-key': apiKey,
      };
}
