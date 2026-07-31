/// The seam between SHIFT AI and whatever is hosting its account data.
///
/// One interface, one implementation at a time, and **no file outside
/// `lib/backend/` may know which one is in use** — enforced by
/// `tool/scan_backend_boundary.py` rather than remembered. Changing hosts is
/// then a new class in this folder, not a refactor of the app.
///
/// This is the same shape the codebase already uses for the things that have
/// had to be swappable: `ChatService` (mock/live), `WebAudioPlayer` (io/web),
/// `PersistenceService`. Nothing new is being invented here.
library;

/// A signed-in account.
class ShiftAccount {
  final String id;
  final String? email;
  final String? displayName;

  const ShiftAccount({required this.id, this.email, this.displayName});
}

/// A live session. [accessToken] is what authorises a request; [expiresAt] is
/// when it stops doing so, which is why the refresh token is kept beside it.
class ShiftSession {
  final ShiftAccount account;
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  const ShiftSession({
    required this.account,
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

  /// Treated as expired a minute early, so a request is never sent with a
  /// token that dies in flight.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'id': account.id,
        'email': account.email,
        'displayName': account.displayName,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static ShiftSession? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id'] as String?;
    final token = json['accessToken'] as String?;
    final expires = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (id == null || token == null || expires == null) return null;
    return ShiftSession(
      account: ShiftAccount(
        id: id,
        email: json['email'] as String?,
        displayName: json['displayName'] as String?,
      ),
      accessToken: token,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: expires,
    );
  }
}

/// What a client is allowed to know about a stored provider key.
///
/// Never the key. The server encrypts it, uses it, and returns only enough to
/// recognise it — which is the whole reason the vault is worth having over
/// storing keys on the device.
class ProviderKeyInfo {
  final String id;
  final String provider;
  final String lastFour;

  /// True when this is SHIFT's own key, spent under a membership, rather than
  /// one the member added.
  final bool managed;
  final DateTime addedAt;

  const ProviderKeyInfo({
    required this.id,
    required this.provider,
    required this.lastFour,
    required this.managed,
    required this.addedAt,
  });
}

enum MembershipStatus { none, trialing, active, pastDue, canceled }

/// The membership, and the meter that bounds it.
///
/// [spentMicros] and [ceilingMicros] are millionths of a dollar. They travel
/// together because either alone is misleading: spend without a ceiling looks
/// unbounded, a ceiling without spend looks unused.
class Membership {
  final MembershipStatus status;
  final String? plan;
  final DateTime? renewsAt;
  final int ceilingMicros;
  final int spentMicros;

  const Membership({
    this.status = MembershipStatus.none,
    this.plan,
    this.renewsAt,
    this.ceilingMicros = 0,
    this.spentMicros = 0,
  });

  static const Membership none = Membership();

  bool get isActive =>
      status == MembershipStatus.active || status == MembershipStatus.trialing;

  /// Whether one more call may be paid for with SHIFT's keys. Mirrors
  /// `shift.within_ceiling()` in the schema — the database is the authority,
  /// this is so the UI can say why before the request is refused.
  bool get canSpendManaged => isActive && spentMicros < ceilingMicros;

  double get fractionUsed =>
      ceilingMicros <= 0 ? 0 : (spentMicros / ceilingMicros).clamp(0, 1);
}

/// A turn to run on a schedule (G5).
class ScheduledTask {
  final String id;
  final String name;
  final String cron;
  final String prompt;
  final bool enabled;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  const ScheduledTask({
    required this.id,
    required this.name,
    required this.cron,
    required this.prompt,
    this.enabled = true,
    this.lastRunAt,
    this.nextRunAt,
  });
}

/// Why a backend call did not work, in terms the UI can say out loud.
///
/// Deliberately few. "The network is down", "you are not signed in", "that
/// password is wrong" and "you are over your limit" lead to different things
/// for the user to do; every other failure leads to "try again", so collapsing
/// them into [unavailable] loses nothing and stops the UI growing a branch per
/// HTTP status.
enum BackendProblem {
  /// No backend is configured — this build talks to nothing.
  notConfigured,

  /// Signed out, or the session expired and could not be refreshed.
  notSignedIn,

  /// Wrong email or password, or an account that already exists.
  credentials,

  /// The account was created and cannot be used until the emailed link is
  /// followed.
  ///
  /// Its own member rather than a [credentials] failure, because it is not a
  /// failure at all — the sign-up worked. Reported as an error it reaches the
  /// user in red under a form that just did what they asked, which reads as
  /// "that did not work" and invites them to try again with a different
  /// password.
  confirmationRequired,

  /// The account is over its ceiling, or has no membership to spend under.
  overLimit,

  /// Anything else: offline, a 500, a timeout.
  unavailable,
}

class BackendException implements Exception {
  final BackendProblem problem;

  /// Shown to the user. A sentence, about what happened and what to do — never
  /// an exception's `toString()`.
  ///
  /// The distinction is not pedantry: the first version of this leaked
  /// `ClientException: Failed to fetch, uri=https://[project].supabase.co/
  /// auth/v1/token?grant_type=password` into a sign-in form, which tells the
  /// person who typed a password nothing they can act on and tells anyone
  /// reading over their shoulder the project's address.
  final String message;

  /// The underlying failure, for logs. Never rendered.
  final String? detail;

  const BackendException(this.problem, this.message, {this.detail});

  @override
  String toString() =>
      'BackendException($problem): $message${detail == null ? '' : ' [$detail]'}';
}

/// The human sentence for a problem, used wherever the server did not supply
/// one of its own.
///
/// Kept beside the enum so adding a member forces a decision about what the
/// user is told, rather than leaving it to whichever call site notices.
String defaultMessageFor(BackendProblem problem) => switch (problem) {
      BackendProblem.notConfigured =>
        'This build has no server behind it. Keys stay on this device.',
      BackendProblem.notSignedIn => 'Sign in to do that.',
      BackendProblem.credentials => 'That email and password did not match.',
      BackendProblem.confirmationRequired =>
        'Account created. Check your email for the confirmation link, then '
            'sign in.',
      BackendProblem.overLimit =>
        'You have used everything your plan covers this month.',
      BackendProblem.unavailable =>
        'Could not reach the server. Check your connection and try again.',
    };

/// Everything the app asks of a server.
///
/// Every method may throw [BackendException]; none returns null to mean
/// failure, because a null that might mean "none" or might mean "we could not
/// ask" is the ambiguity that leads to an empty screen where an error belongs.
abstract class ShiftBackend {
  /// False when this build has no server behind it, which is the default and
  /// must stay a working state: the app runs unauthenticated on local keys
  /// exactly as it does today, and the public demo has no account at all.
  bool get isConfigured;

  /// The current session, or null when signed out.
  ShiftSession? get session;

  /// Emits on every sign-in, sign-out and refresh.
  Stream<ShiftSession?> get sessionChanges;

  /// Restores a stored session, refreshing it if it has expired. Returns null
  /// when there is nothing to restore — not an error.
  Future<ShiftSession?> restore();

  Future<ShiftSession> signIn({required String email, required String password});

  Future<ShiftSession> signUp({required String email, required String password});

  Future<void> signOut();

  /// Metadata only — the secrets themselves never come back.
  Future<List<ProviderKeyInfo>> listProviderKeys();

  /// Stores a key. Write-only by design: it goes to the server encrypted and
  /// is never readable again, by this client or any other.
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  });

  Future<void> deleteProviderKey(String id);

  /// Stores one of SHIFT's own keys, which every paying member spends.
  ///
  /// Refused unless the caller is an admin, and refused *server-side* — the
  /// flag is a column only the server can write, not a claim in a token.
  /// Throws [BackendProblem.notSignedIn] when the caller is not allowed,
  /// which is deliberately the same answer an unauthenticated caller gets.
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  });

  /// Which providers a membership currently covers. Names only — a member has
  /// no use for the keys and never sees them.
  Future<List<String>> includedProviders();

  /// Whether the signed-in account may manage SHIFT's own keys.
  ///
  /// Asked of the server rather than read from the token: admin is a column
  /// only the server can write, and a claim baked into a token that lives for
  /// an hour on a device would keep working for that hour after it was
  /// revoked. False whenever the answer is not a clear yes — including when
  /// the request fails, since a network error is not a promotion.
  ///
  /// This gates *presentation only*. The endpoint checks the same column
  /// itself and refuses regardless, so a client that lied here would gain
  /// nothing but a form that returns 403.
  Future<bool> isAdmin();

  Future<Membership> membership();

  /// Where to send a provider call that the membership pays for, and what
  /// authorises it — or null when this account cannot spend one.
  ///
  /// Returns the *target and headers* rather than a token, for two reasons.
  /// The session may need refreshing first, and only this layer knows how; and
  /// a method that handed back a raw token would invite callers to build their
  /// own requests with it, which is how a token ends up somewhere it should not
  /// be. The caller gets something it can only use for this.
  ///
  /// Null is an ordinary answer — signed out, no membership, or a provider
  /// SHIFT does not cover — and means "use your own key, or the mock". The
  /// server checks entitlement again regardless; this is so the app can decide
  /// without a round trip, not so the app can be trusted.
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
    String provider,
  );

  /// A URL to open to start or manage a subscription. The app never handles
  /// card details; it hands off to the payment provider's own page.
  Future<Uri> billingPortal({String? plan});

  Future<List<ScheduledTask>> listScheduledTasks();

  Future<ScheduledTask> saveScheduledTask(ScheduledTask task);

  Future<void> deleteScheduledTask(String id);

  /// Releases anything held open. Called when the app shuts down.
  void dispose();
}
