import 'access.dart';
import 'registry.dart';
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

/// The blocked case again, when we know **who** was being called and that we
/// were in a browser.
///
/// The generic [sentenceForUnreachable] blames the browser and prescribes *try
/// another one*. Against a provider that may not allow calls from a web page at
/// all, that is an instruction to keep doing the one thing that cannot work —
/// and it is what a real report ("some keys are not working, I tried Chrome and
/// Brave") acted on.
///
/// "May not", not "does not": whether these providers send CORS headers is not
/// established. What *is* established, by measurement, is that Claude and
/// Gemini do — so they keep the generic sentence, because for them a blocked
/// request really is something local.
String sentenceForBrowserBlocked(ProviderDescriptor? provider,
    {required bool onWeb}) {
  if (!onWeb || provider == null || provider.webAccess == WebAccess.verified) {
    return sentenceForUnreachable(Reach.up);
  }
  return '${provider.displayName} may not allow calls from a web page. Claude '
      'and Gemini are confirmed to work in a browser; other providers work in '
      'the desktop app, where this restriction does not exist. A content '
      'blocker can also cause this.';
}

/// A request that was accepted and then never answered. Distinct from
/// unreachable on purpose: waiting longer might work, which is not true of
/// anything above.
const String sentenceForTimeout =
    'The provider did not answer in time. Try again.';

/// Why nothing could run a step, in the words that name the actual reason.
///
/// [what] is the plural noun for the step's output — "images", "writing" — so
/// one function serves every capability without a switch per executor.
///
/// **Five states shared one sentence**, and the one they shared was the least
/// useful of them: *"Add a key in Settings, or start a plan."* said to someone
/// who had both. Which state it is decides who can fix it and how, so each gets
/// its own — the same split [sentenceForUnreachable] made for network faults,
/// and made for the same reason.
String sentenceForNoProvider(
  String what, {
  required Entitlement entitlement,
  required bool signedIn,
}) {
  if (!signedIn) {
    return 'No provider is set up for $what yet. Add a key in Settings, '
        'or sign in and start a plan.';
  }
  // Ordered by what the reader can do about it. "Couldn't check" first, because
  // every sentence below it would be a claim about a plan nobody has read.
  if (!entitlement.known) {
    return "Couldn't check what your plan covers just now, and there is no key "
        'on this device for $what. Try again in a moment.';
  }
  if (entitlement.overCeiling) {
    return "You've used this month's allowance, and there is no key on this "
        'device for $what. Add your own key to keep going.';
  }
  if (!entitlement.canSpendManaged) {
    return 'You do not have an active plan, and there is no key on this device '
        'for $what. Start a plan, or add a key in Settings.';
  }
  return "Your plan doesn't cover $what yet, and there is no key on this "
      'device for it. Add a key in Settings.';
}

/// The signed-out answer, and the executors' default.
///
/// A `static const` default has to be a top-level function, which is also why
/// this is the shape it is rather than a closure with a captured entitlement.
String defaultUnavailable(String what) =>
    sentenceForNoProvider(what, entitlement: Entitlement.none, signedIn: false);

/// Sentences already written for a reader.
///
/// A provider's own error text is not shown: it tells the reader nothing they
/// can act on, and occasionally tells them something they should not see. This
/// is the allowlist that lets a message we wrote pass back through.
final Set<String> writtenSentences = {
  for (final status in [400, 401, 402, 403, 404, 429, 500, 529])
    sentenceForStatus(status),
  for (final reach in Reach.values) sentenceForUnreachable(reach),
  // Every provider's variant, or the one sentence in this file that names a
  // provider would be filtered out by [readErrorFrame] and replaced with the
  // generic 500 — an allowlist quietly undoing the fix it was protecting.
  for (final provider in kProviders)
    sentenceForBrowserBlocked(provider, onWeb: true),
  sentenceForTimeout,
};
