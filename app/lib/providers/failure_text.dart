import 'streaming/reachability.dart';

/// Every sentence a provider failure can be reported as, in one place.
///
/// One file rather than one per client, because the alternative is two mappings
/// that disagree — and because a person reading a failure card should not be
/// able to tell which of six wire clients produced it.
///
/// The rule for every sentence here: **say what happened and who can fix it.**
/// "That step could not be completed" satisfies neither, which is why it is the
/// last resort rather than the default.

/// What the provider said, when it said anything.
String sentenceForStatus(int status) => switch (status) {
      400 => 'The provider rejected that request.',
      401 || 403 =>
        'That key was rejected. Check it is complete and still active.',
      404 => 'That model is not available on this key.',
      429 => 'Rate limited. Try again in a moment.',
      402 => 'That provider account is out of credit.',
      529 => 'The provider is overloaded right now.',
      _ => 'The provider could not complete that step.',
    };

/// What to say when **no status arrived at all** — the request did not
/// complete, so there is nothing to read.
///
/// This is the whole reason [Reach] exists. Until it did, all three of these
/// shared one sentence about the connection, so a blocked request and a flat
/// battery of a network read the same and only one of them was ever true.
String sentenceForUnreachable(Reach reach) => switch (reach) {
      Reach.down => 'Your device is offline. The request never left.',
      Reach.up => 'The request was blocked before it reached the provider — '
          'usually a content blocker or a private-browsing shield. Allow this '
          'site, or try another browser.',
      Reach.unknown =>
        'Could not reach the provider. Check your connection and try again.',
    };

/// A request that was accepted and then never answered. Distinct from
/// unreachable on purpose: waiting longer might work, which is not true of
/// anything above.
const String sentenceForTimeout =
    'The provider did not answer in time. Try again.';

/// Sentences already written for a reader.
///
/// A provider's own error text is not shown: it tells the reader nothing they
/// can act on, and occasionally tells them something they should not see. This
/// is the allowlist that lets a message we wrote pass back through.
final Set<String> writtenSentences = {
  for (final status in [400, 401, 402, 403, 404, 429, 500, 529])
    sentenceForStatus(status),
  for (final reach in Reach.values) sentenceForUnreachable(reach),
  sentenceForTimeout,
};
