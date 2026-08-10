import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/failure_text.dart';
import 'package:shift/providers/streaming/reachability.dart';

/// The point of this wave, asserted directly: four faults that used to share
/// one sentence about the connection now say four different things.
void main() {
  group('a failure with no status', () {
    test('each reachability answer produces a different sentence', () {
      final said = {
        for (final reach in Reach.values) sentenceForUnreachable(reach),
      };
      expect(said, hasLength(Reach.values.length),
          reason: 'two states sharing a sentence is the defect being removed');
    });

    test('offline says the request never left', () {
      expect(sentenceForUnreachable(Reach.down), contains('offline'));
    });

    test('reachable-but-failed blames the block, not the connection', () {
      final blocked = sentenceForUnreachable(Reach.up);
      expect(blocked, contains('blocked'));
      // The regression this must not reintroduce: telling someone whose
      // network is demonstrably fine to check their connection.
      expect(blocked.toLowerCase(), isNot(contains('check your connection')));
    });

    test('off-web keeps exactly the wording that shipped', () {
      // `unknown` is every desktop and mobile build. There is no browser there
      // to block anything, so claiming one would be inventing a diagnosis —
      // and this pins that the change is additive rather than a reword.
      expect(
        sentenceForUnreachable(Reach.unknown),
        'Could not reach the provider. Check your connection and try again.',
      );
    });
  });

  group('a failure with a status', () {
    test('a rejected key and a rate limit do not read alike', () {
      expect(sentenceForStatus(401), isNot(sentenceForStatus(429)));
      expect(sentenceForStatus(401), sentenceForStatus(403));
    });

    test('an unknown status still says something true', () {
      expect(sentenceForStatus(418), isNotEmpty);
    });
  });

  test('a timeout is its own thing', () {
    // Distinct from unreachable on purpose: waiting longer might work here,
    // which is not true of anything the probe reports.
    expect(sentenceForTimeout, isNot(sentenceForUnreachable(Reach.unknown)));
    expect(sentenceForTimeout, isNot(sentenceForUnreachable(Reach.down)));
  });

  test('every sentence we wrote is allowed back through', () {
    // `_readable` gates the provider's own error text out and ours in. A
    // sentence missing from this set would be replaced by the generic one at
    // the last moment, which is how careful wording silently stops shipping.
    for (final reach in Reach.values) {
      expect(writtenSentences, contains(sentenceForUnreachable(reach)));
    }
    expect(writtenSentences, contains(sentenceForTimeout));
    for (final status in [400, 401, 402, 403, 404, 429, 500, 529]) {
      expect(writtenSentences, contains(sentenceForStatus(status)));
    }
  });
}
