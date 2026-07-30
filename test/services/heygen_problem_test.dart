import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/heygen_client.dart';

void main() {
  group('heygenProblem', () {
    test('names the cause each status actually has', () {
      // A Heygen key that could not render used to fall through in silence to
      // the simulated card, so "the Heygen API is not working" was all anyone
      // could tell. These strings are what reaches the chat instead.
      expect(heygenProblem(400, '{}'), contains('avatar or voice'));
      expect(heygenProblem(401, '{}'), contains('app.heygen.com'));
      expect(heygenProblem(402, '{}'), contains('credits'));
      expect(heygenProblem(404, '{}'), contains('retired'));
      expect(heygenProblem(429, '{}'), contains('rate-limited'));
    });

    test('the raw body is always included', () {
      // Heygen's own message is more specific than anything guessed from the
      // status code, so it is never dropped.
      for (final code in [400, 401, 402, 404, 429, 500]) {
        expect(heygenProblem(code, 'RAW-BODY'), contains('RAW-BODY'),
            reason: '$code');
      }
    });

    test('an unrecognised status still says something useful', () {
      expect(heygenProblem(503, 'down'), contains('503'));
    });
  });
}
