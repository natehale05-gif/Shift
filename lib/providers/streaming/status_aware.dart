import 'dart:convert';

import '../failure_text.dart';
import 'reachability.dart';
import 'sse_client.dart';

/// Turns a transport-level failure into an `error` frame that says which
/// failure it was.
///
/// Shared by every wire client, deliberately. v1 put this inside its Anthropic
/// path and the other providers reported a bare "that step could not be
/// completed" for a rejected key, a rate limit and an outage alike — three
/// problems, three fixes, and only one of them the user's.
///
/// Re-emitted as a frame rather than thrown, so there is exactly one place that
/// turns a provider problem into a sentence rather than several that can
/// disagree.
///
/// [blocked] overrides the sentence used when nothing ever came back and the
/// device is otherwise online. It exists because *who was being called* decides
/// the right advice there, and the wire clients do not know — one of them
/// serves four providers. The executor knows, so it supplies the sentence and
/// this stays the only place that emits one.
Stream<SseEvent> statusAware(
  Stream<SseEvent> events, {
  required String host,
  required Future<Reach> Function() reach,
  String? blocked,
  bool managed = false,
}) async* {
  String? sentence;
  String? detail;

  try {
    // `await for`, not `yield*`. A `yield*` forwards a stream's error straight
    // to the consumer without ever throwing inside this function, so a catch
    // around it never runs and the status is lost anyway — a fix that looks
    // right, compiles, and does nothing.
    await for (final event in events) {
      yield event;
    }
    return;
  } on SseHttpException catch (e) {
    // Which reader depends on who answered. A managed call's 4xx often came
    // from our own proxy, and reading it as the provider's is how a member was
    // told to check a key they do not have.
    sentence = managed
        ? sentenceForManagedStatus(e.statusCode, e.body)
        : sentenceForStatus(e.statusCode);
    detail = 'HTTP ${e.statusCode} from $host';
  } on SseTimeoutException catch (e) {
    sentence = sentenceForTimeout;
    detail = '$e · $host';
  } catch (e) {
    // No status at all: the request never completed. From in here a browser
    // refusing it looks exactly like being offline, which is why the sentence
    // is chosen by asking whether *anything* is reachable rather than guessed.
    //
    // The exception is kept, not discarded. `catch (_)` threw away the one
    // fact that distinguishes a blocked fetch from a stalled socket, at the
    // only point in the program where that fact exists.
    detail = '$e · $host';
  }

  // Outside the try: awaiting inside a catch and then yielding is legal but
  // reads as if the probe were part of the failing operation, and it is not.
  // Guarded rather than `??=`. The probe must only run when no status arrived:
  // `??=` gave that for free by not evaluating its right side, and hoisting the
  // await out to reuse the answer quietly cost *every* failure — a rejected key
  // included — an extra request answering a question the status had settled.
  if (sentence == null) {
    final where = await reach();
    sentence = where == Reach.up && blocked != null
        ? blocked
        : sentenceForUnreachable(where);
  }

  yield SseEvent(
    event: 'error',
    data: jsonEncode({
      'error': {'message': sentence, 'shift_detail': detail}
    }),
  );
}

/// The sentence and the detail carried by an `error` frame.
///
/// Sentences we wrote pass through; anything the provider itself said does not,
/// because a raw API message tells the reader nothing they can act on and
/// occasionally tells them something they should not see.
({String reason, String? detail}) readErrorFrame(Map<String, dynamic> payload) {
  final error = payload['error'];
  final map = error is Map<String, dynamic> ? error : const {};
  final message = map['message'];
  final text = message is String ? message : '';

  final reason = writtenSentences.contains(text)
      ? text
      : text.contains('credit') || text.contains('billing')
          ? sentenceForStatus(402)
          : sentenceForStatus(500);

  return (reason: reason, detail: map['shift_detail'] as String?);
}
