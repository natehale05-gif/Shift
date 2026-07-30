import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/backend/backend_config.dart';

void main() {
  group('BackendConfig', () {
    test('an ordinary build is configured', () {
      // The test that was missing, and the one that would have caught the
      // whole thing: every deploy compiled `SHIFT_SUPABASE_URL=""`, so the app
      // shipped on NoBackend and hid its account section — correctly, and
      // silently. Sign-in was absent from the live site for a release and
      // nothing failed, because nothing asserted that a build has a backend.
      final config = BackendConfig.fromEnvironment();

      expect(config, isNotNull,
          reason: 'a build with no overrides must reach the live project');
      expect(config!.url, startsWith('https://'));
      expect(config.url, endsWith('.supabase.co'));
      expect(config.anonKey, isNotEmpty);
    });

    test('the anon key is a token for the anon role and nothing more', () {
      // Committed on purpose (see backend_config.dart), and safe only because
      // of what it is. If this ever stops being an `anon` token — a
      // service-role key pasted in by mistake, say — that is a key with
      // `bypassrls` shipped to every visitor, and it must fail here loudly
      // rather than in production quietly.
      final key = BackendConfig.fromEnvironment()!.anonKey;

      expect(key, isNot(contains('service_role')));
      expect(key, isNot(contains('secret')));

      if (key.startsWith('eyJ')) {
        // A legacy JWT: the middle segment carries the role in cleartext
        // base64, so it can be read without verifying anything.
        final payload = key.split('.')[1];
        final decoded = String.fromCharCodes(
          _base64Url(payload),
        );
        expect(decoded, contains('"role":"anon"'));
      }
    });
  });
}

/// Decodes a base64url segment, padding it back to a multiple of four.
List<int> _base64Url(String segment) {
  final padded = segment.padRight((segment.length + 3) ~/ 4 * 4, '=');
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final bytes = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final char in padded.split('')) {
    if (char == '=') break;
    buffer = (buffer << 6) | alphabet.indexOf(char);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xFF);
    }
  }
  return bytes;
}
