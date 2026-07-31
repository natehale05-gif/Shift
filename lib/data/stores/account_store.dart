import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/shift_backend.dart';
import '../../backend/setup_probe.dart';
import '../../providers/clients/provider_access.dart';
import '../persistence/persistence_service.dart';

/// What the sign-in form is doing right now.
///
/// [checking] exists so the UI can tell "we have not looked yet" from "you are
/// signed out". Without it, every launch flashes a sign-in prompt at someone
/// who is already signed in, for as long as the stored session takes to load.
enum AccountPhase { checking, signedOut, working, signedIn }

/// The app's view of the account: who is signed in, and what their membership
/// allows.
///
/// Talks to [ShiftBackend] and nothing else, so which host is behind it is not
/// a fact this store — or anything above it — can observe.
class AccountStore extends ChangeNotifier {
  final ShiftBackend backend;
  final PersistenceService persistence;

  AccountPhase _phase = AccountPhase.checking;
  ShiftAccount? _account;
  Membership _membership = Membership.none;
  List<ProviderKeyInfo> _serverKeys = const [];
  List<String> _includedProviders = const [];
  bool _isAdmin = false;
  String? _problem;
  String? _notice;

  StreamSubscription<ShiftSession?>? _sessions;

  AccountStore({required this.backend, required this.persistence}) {
    _sessions = backend.sessionChanges.listen((session) {
      _account = session?.account;
      if (session == null && _phase == AccountPhase.signedIn) {
        _phase = AccountPhase.signedOut;
        _membership = Membership.none;
        _serverKeys = const [];
        notifyListeners();
      }
    });
  }

  /// False when this build has no server behind it — which is every build so
  /// far, and the public demo permanently. The UI hides account surfaces
  /// entirely rather than offering a sign-in that cannot work.
  bool get isConfigured => backend.isConfigured;

  AccountPhase get phase => _phase;
  ShiftAccount? get account => _account;
  Membership get membership => _membership;
  List<ProviderKeyInfo> get serverKeys => List.unmodifiable(_serverKeys);

  /// Providers a membership covers, by name. Empty when signed out or when
  /// SHIFT has no keys of its own loaded yet.
  List<String> get includedProviders => List.unmodifiable(_includedProviders);

  /// Whether this account may manage SHIFT's own provider keys.
  ///
  /// Comes from the server on every refresh, never from the token. False until
  /// it has been asked, which is the safe direction: the admin surface stays
  /// hidden while the answer is unknown, and the endpoint behind it refuses a
  /// non-admin anyway.
  bool get isAdmin => _isAdmin;

  /// The last failure, in words meant for a person. Cleared by the next
  /// attempt, so a stale error never sits under a form that has since worked.
  String? get problem => _problem;

  /// Something that worked but is not finished — today, only "we sent you a
  /// confirmation email". Separate from [problem] because showing it in red
  /// under a form that just succeeded tells the user the opposite of what
  /// happened.
  String? get notice => _notice;

  bool get isSignedIn => _phase == AccountPhase.signedIn;
  bool get isBusy => _phase == AccountPhase.working;

  /// Restores a stored session on launch.
  ///
  /// Never throws and never surfaces an error: not being signed in is the
  /// ordinary state, and someone who has not opened the app in a month should
  /// meet a sign-in screen rather than a failure.
  Future<void> restore() async {
    if (!isConfigured) {
      _phase = AccountPhase.signedOut;
      notifyListeners();
      return;
    }
    try {
      final session = await backend.restore();
      _account = session?.account;
      _phase = session == null ? AccountPhase.signedOut : AccountPhase.signedIn;
    } catch (_) {
      _phase = AccountPhase.signedOut;
    }
    notifyListeners();
    if (isSignedIn) unawaited(refresh());
  }

  Future<bool> signIn({required String email, required String password}) =>
      _attempt(() => backend.signIn(email: email, password: password));

  Future<bool> signUp({required String email, required String password}) =>
      _attempt(() => backend.signUp(email: email, password: password));

  /// Runs one credential attempt, and reports it as a bool rather than by
  /// throwing — a form needs to know whether to close, not to catch.
  Future<bool> _attempt(Future<ShiftSession> Function() call) async {
    if (!isConfigured) {
      _problem = 'This build has no server behind it.';
      notifyListeners();
      return false;
    }
    _phase = AccountPhase.working;
    _problem = null;
    _notice = null;
    notifyListeners();

    try {
      final session = await call();
      _account = session.account;
      _phase = AccountPhase.signedIn;
      notifyListeners();
      unawaited(refresh());
      return true;
    } on BackendException catch (e) {
      // Sign-up on a project that confirms email addresses ends here, and it
      // is the one failure that is not one: the account exists.
      if (e.problem == BackendProblem.confirmationRequired) {
        _notice = e.message;
      } else {
        _problem = e.message;
      }
      _phase = AccountPhase.signedOut;
      notifyListeners();
      return false;
    } catch (e) {
      // Anything the backend did not classify still has to reach the user as
      // a sentence rather than as a stuck spinner.
      _problem = 'Could not reach the server. Try again.';
      _phase = AccountPhase.signedOut;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await backend.signOut();
    } catch (_) {
      // Signing out locally must succeed even when telling the server fails,
      // or a network blip strands someone signed in on a device they wanted
      // to leave.
    }
    _account = null;
    _membership = Membership.none;
    _serverKeys = const [];
    _includedProviders = const [];
    _isAdmin = false;
    _problem = null;
    _notice = null;
    _phase = AccountPhase.signedOut;
    notifyListeners();
  }

  /// Re-reads membership and stored keys.
  ///
  /// Failures here are deliberately quiet: this runs in the background after
  /// sign-in, and an error banner for a refresh nobody asked for is noise. The
  /// values simply stay as they were.
  Future<void> refresh() async {
    if (!isSignedIn) return;
    try {
      final results = await Future.wait([
        backend.membership(),
        backend.listProviderKeys(),
        backend.includedProviders(),
        backend.isAdmin(),
      ]);
      _membership = results[0] as Membership;
      _serverKeys = results[1] as List<ProviderKeyInfo>;
      _includedProviders = results[2] as List<String>;
      _isAdmin = results[3] as bool;
      notifyListeners();
    } catch (_) {
      // Left as-is on purpose.
    }
  }

  /// Stores a provider key on the server. Returns the error to show, or null
  /// on success.
  Future<String?> putProviderKey({
    required String provider,
    required String secret,
  }) async {
    try {
      await backend.putProviderKey(provider: provider, secret: secret);
      await refresh();
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Try again.';
    }
  }

  /// Stores one of SHIFT's own keys. Returns the error to show, or null.
  ///
  /// Whether the caller is allowed is decided by the server; this only
  /// reports what it said.
  Future<String?> putPlatformKey({
    required String provider,
    required String secret,
  }) async {
    try {
      await backend.putPlatformKey(provider: provider, secret: secret);
      await refresh();
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (_) {
      return defaultMessageFor(BackendProblem.unavailable);
    }
  }

  /// Where a call for [provider] goes when the membership pays for it, or
  /// null when it does not.
  ///
  /// Three conditions, checked here so a turn does not make a request it
  /// already knows will be refused: signed in, a subscription that is active
  /// and under its ceiling, and a provider the plan actually covers. The
  /// server checks all three again — this is a shortcut, not the gate.
  Future<ProviderAccess?> managedAccess(String provider) async {
    if (!isSignedIn || !_membership.canSpendManaged) return null;
    if (!_includedProviders.contains(provider)) return null;

    final call = await backend.managedProviderCall(provider);
    if (call == null) return null;
    return ManagedAccess(base: call.base, headers: call.headers);
  }

  /// The covered providers, as the set routing needs synchronously.
  ///
  /// Empty unless the plan can actually pay right now, so a lapsed or spent
  /// membership stops steering the router the moment the meter says so.
  Set<String> get spendableProviders =>
      isSignedIn && _membership.canSpendManaged
          ? _includedProviders.toSet()
          : const {};

  /// Grants a membership. Returns the error to show, or null on success.
  ///
  /// Whether the caller may is decided by the server; this reports what it
  /// said. The refresh afterwards is what makes the change visible in the same
  /// screen that made it — granting yourself a plan and still seeing "no
  /// membership" would read as a failure.
  Future<String?> grantMembership({
    String? email,
    String status = 'active',
    String plan = 'granted',
    required int ceilingMicros,
  }) async {
    try {
      await backend.grantMembership(
        email: email,
        status: status,
        plan: plan,
        ceilingMicros: ceilingMicros,
      );
      await refresh();
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (_) {
      return defaultMessageFor(BackendProblem.unavailable);
    }
  }

  /// Host settings that have to be changed somewhere this app cannot reach.
  /// The list, and every URL in it, comes from the backend — naming a vendor
  /// is its job, not the UI's.
  List<SetupLink> get setupLinks => backend.setupLinks();

  /// Sends one call through the proxy and says what happened.
  ///
  /// The point of this existing at all: from inside a chat, "not deployed",
  /// "not entitled" and "the key is wrong" all look the same — a reply that
  /// did not arrive. Here they are three different sentences.
  Future<ProxyProbeResult> testProxy({String provider = 'anthropic'}) async {
    if (!isConfigured || !isSignedIn) return proxyNotSignedIn;

    final answer = await backend.probeProxy(provider);
    if (answer == null) return proxyUnreachable;

    final result = readProxyResponse(answer.status, answer.body);
    // A working call spends a token or two, so the meter moved.
    if (result.isWorking) await refresh();
    return result;
  }

  Future<String?> deleteProviderKey(String id) async {
    try {
      await backend.deleteProviderKey(id);
      await refresh();
      return null;
    } on BackendException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Try again.';
    }
  }

  @override
  void dispose() {
    _sessions?.cancel();
    super.dispose();
  }
}
