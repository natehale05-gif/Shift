import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/backend/setup_probe.dart';

void main() {
  group('readProxyResponse', () {
    test('a 404 means the function was never deployed', () {
      // The distinction the whole card exists for. From inside a chat this is
      // indistinguishable from every other failure — a reply that never came.
      final result = readProxyResponse(404, '');

      expect(result.outcome, ProxyOutcome.notDeployed);
      expect(result.message, contains('not deployed'));
      expect(result.isWorking, isFalse);
    });

    test('a 402 means it *is* deployed and is refusing this account', () {
      final result = readProxyResponse(402, '');

      expect(result.outcome, ProxyOutcome.notEntitled);
      expect(result.message, isNot(contains('deployed')),
          reason: 'saying "not deployed" here sends someone to fix CI when '
              'the server is running perfectly');
    });

    test('the server\'s own reason wins over the generic sentence', () {
      final result = readProxyResponse(
        402,
        '{"message":"You have used everything your plan covers this month."}',
      );

      expect(result.message, contains('everything your plan covers'));
    });

    test('a 503 points at the missing key rather than at the server', () {
      final result = readProxyResponse(503, '');

      expect(result.outcome, ProxyOutcome.serverNotReady);
      expect(result.message, contains('Included with membership'));
    });

    test('a 503 the server explained says the server\'s reason, not ours', () {
      // 503 covers two things and only the server knows which: no key for this
      // provider, and a server missing one of its own settings. Overwriting
      // its sentence with the commoner of the two sends someone to paste a key
      // they have already pasted.
      final result = readProxyResponse(
        503,
        '{"message":"The server is missing SHIFT_KMS_KEY."}',
      );

      expect(result.message, contains('SHIFT_KMS_KEY'));
      expect(result.message, isNot(contains('Included with membership')));
    });

    test('a provider rejection is named as the provider\'s', () {
      // The proxy forwards the provider's status, so a 401 here is Anthropic
      // refusing the stored key — not our auth.
      final result = readProxyResponse(
        400,
        '{"error":{"message":"invalid x-api-key"}}',
      );

      expect(result.outcome, ProxyOutcome.providerRejected);
      expect(result.message, contains('invalid x-api-key'));
    });

    test('a 401 is our auth, not the provider\'s', () {
      expect(readProxyResponse(401, '').outcome, ProxyOutcome.notSignedIn);
    });

    test('a 5xx from the provider says to wait, not to change anything', () {
      final result = readProxyResponse(502, '');

      expect(result.outcome, ProxyOutcome.providerRejected);
      expect(result.message, contains('Try again'));
    });

    test('a 200 is the only thing that reads as working', () {
      final result = readProxyResponse(200, 'data: {"type":"message_start"}');

      expect(result.outcome, ProxyOutcome.working);
      expect(result.isWorking, isTrue);
    });

    test('every outcome produces a distinct sentence', () {
      // Different causes needing different actions. Two of them sharing a
      // sentence would be the diagnostic failing at its only job.
      //
      // The three 503s are here because a status is not a diagnosis: one
      // status now covers three server-side states, and they are only
      // distinguishable by the words the server sent with them. A 402 whose
      // real cause was an entitlement check that could not run is exactly how
      // this went wrong once already.
      final messages = [
        readProxyResponse(404, ''),
        readProxyResponse(402, ''),
        readProxyResponse(503, ''),
        readProxyResponse(503, '{"message":"The server is missing SHIFT_KMS_KEY."}'),
        readProxyResponse(503, '{"message":"Could not check your plan right now."}'),
        readProxyResponse(200, ''),
        proxyUnreachable,
        proxyNotSignedIn,
      ].map((r) => r.message).toSet();

      expect(messages, hasLength(8));
    });

    test('a body that is not JSON does not become the message', () {
      final result = readProxyResponse(500, '<html>gateway timeout</html>');

      expect(result.message, isNot(contains('<html>')));
      expect(result.detail, isNull);
    });

    test('a very long server message is truncated', () {
      final result = readProxyResponse(
        402,
        '{"message":"${'x' * 900}"}',
      );

      expect(result.message.length, lessThan(300));
      expect(result.message, endsWith('…'));
    });
  });
}
