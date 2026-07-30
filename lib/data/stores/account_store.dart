import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/shift_backend.dart';
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
  String? _problem;

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

  /// The last failure, in words meant for a person. Cleared by the next
  /// attempt, so a stale error never sits under a form that has since worked.
  String? get problem => _problem;

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
    notifyListeners();

    try {
      final session = await call();
      _account = session.account;
      _phase = AccountPhase.signedIn;
      notifyListeners();
      unawaited(refresh());
      return true;
    } on BackendException catch (e) {
      _problem = e.message;
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
    _problem = null;
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
      ]);
      _membership = results[0] as Membership;
      _serverKeys = results[1] as List<ProviderKeyInfo>;
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
