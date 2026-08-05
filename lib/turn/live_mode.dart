/// What the app can actually do right now, and what to call it.
///
/// This exists because the app spent an evening telling its owner it was in
/// demo mode while it was answering with a real model. Both labels — the chip
/// beside the conversation title and the line under the composer — asked
/// `ApiKeysStore.isLive`, which means "has this device stored a key". That was
/// the same wrong question the turn selector asked, and it survived the fix to
/// the selector because it is asked somewhere else entirely.
///
/// So the question is asked once, here, and the wording lives with it. Two
/// widgets each inventing a sentence about the same state is how they came to
/// disagree with the product.
///
/// Pure, so the wording is testable — which matters more than usual, because
/// the failure mode is not a crash. It is a label that is quietly wrong, and
/// nothing but reading it catches that.
library;

enum LiveCapability {
  /// No key, no plan. Everything is simulated, and saying so is correct.
  demo,

  /// A membership pays for text: chat, code, pages, research. Media is still
  /// simulated, because the proxy forwards chat endpoints only.
  membershipText,

  /// The member's own key. What it covers depends on which providers they
  /// added, which is theirs to know — so the wording does not promise media.
  ownKeys,
}

/// How the app should describe itself.
///
/// [footer] is null when there is nothing worth saying under every message
/// forever. A caution nobody reads twice is furniture.
typedef LiveDescription = ({String chip, String tooltip, String? footer});

LiveCapability liveCapability({
  required bool hasOwnKey,
  required bool hasMembership,
}) {
  // Own keys first, and this is the one place that ordering differs from
  // billing. `_accessFor` spends the *membership* first, because that is what
  // the member is paying for monthly. But for describing what the app can do,
  // a stored key is the broader answer: it is the only thing that makes image
  // and voice turns real, so it is the claim that stays true.
  if (hasOwnKey) return LiveCapability.ownKeys;
  if (hasMembership) return LiveCapability.membershipText;
  return LiveCapability.demo;
}

LiveDescription describeLive(LiveCapability capability) => switch (capability) {
      LiveCapability.demo => (
          chip: 'Simulated',
          tooltip: 'Simulated — add an API key in Settings, or a plan, for '
              'live AI.',
          footer: 'SHIFT AI is in demo mode — responses are simulated.',
        ),
      LiveCapability.membershipText => (
          chip: 'Live',
          tooltip: 'Live on your plan — chat, code and pages run on SHIFT\'s '
              'key, with no key on this device.',
          // Said because it is the surprising half. A member watching a real
          // page get built and then a placeholder image appear should be told
          // which of those was real, rather than working it out.
          footer: 'Images and voice are simulated — your plan covers text.',
        ),
      LiveCapability.ownKeys => (
          chip: 'Live',
          tooltip: 'Live — calls go to the providers you added keys for.',
          footer: null,
        ),
    };
