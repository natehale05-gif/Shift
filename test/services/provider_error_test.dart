import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/clients/provider_error.dart';
import 'package:shift_ai/providers/streaming/sse_client.dart';

/// The exact body from the reported failure.
const _reported = '{"type":"error","error":{"type":"invalid_request_error",'
    '"message":"messages.1.content: \'image\' blocks are not permitted within '
    'assistant turns."},"request_id":"req_011CdYr42wfXBTNKttrHWyjk"}';

void main() {
  group('readableProviderError', () {
    test('keeps the provider\'s sentence and drops the envelope', () {
      // What shipped: the whole JSON blob printed into the chat, filling a
      // phone screen with the one useful sentence buried in the middle.
      final message = readableProviderError(SseHttpException(400, _reported));

      expect(message, contains("'image' blocks are not permitted"));
      expect(message, isNot(contains('{')));
      expect(message, isNot(contains('request_id')));
      expect(message, isNot(contains('invalid_request_error')));
    });

    test('a rejected key says to check the key, not "something went wrong"',
        () {
      // With bring-your-own-key this *is* the diagnosis, so collapsing every
      // failure into one sentence would be worse here than in most apps.
      final message = readableProviderError(
          SseHttpException(401, '{"error":{"message":"invalid x-api-key"}}'));

      expect(message.toLowerCase(), contains('key'));
      expect(message, contains('Settings'));
    });

    test('the four statuses a user can act on each say something different',
        () {
      final byStatus = {
        for (final status in [401, 402, 429, 500])
          status: readableProviderError(SseHttpException(status, '')),
      };

      expect(byStatus[402], contains('credit'));
      expect(byStatus[429]!.toLowerCase(), contains('rate limited'));
      expect(byStatus[500], contains('trouble'));
      expect(byStatus.values.toSet(), hasLength(4),
          reason: 'four causes, four different things to do about them');
    });

    test('an unparseable body still produces a sentence', () {
      final message =
          readableProviderError(SseHttpException(400, '<html>gateway</html>'));

      expect(message, isNot(contains('<html>')));
      expect(message, contains('rejected the request'));
    });

    test('an empty body does not produce a dangling colon', () {
      expect(readableProviderError(SseHttpException(400, '')),
          isNot(endsWith(': ')));
    });

    test('a message shape we do not recognise is not guessed at', () {
      // Inventing an explanation reads as the app making something up.
      final message = readableProviderError(
          SseHttpException(400, '{"unexpected":{"nested":"shape"}}'));
      expect(message, isNot(contains('nested')));
      expect(message, isNot(contains('shape')));
    });

    test('a very long provider message is truncated rather than filling the '
        'screen', () {
      final long = 'x' * 2000;
      final message = readableProviderError(
          SseHttpException(400, '{"error":{"message":"$long"}}'));

      expect(message.length, lessThan(400));
      expect(message, endsWith('…'));
    });

    test('anything that is not an HTTP answer reads as a connection problem',
        () {
      final message = readableProviderError(Exception('SocketException'));
      expect(message, contains('Could not reach'));
      expect(message, isNot(contains('SocketException')));
    });

    test('the provider can be named', () {
      expect(
        readableProviderError(SseHttpException(503, ''), provider: 'Gemini'),
        contains('Gemini'),
      );
    });
  });
}
