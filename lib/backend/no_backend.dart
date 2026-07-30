import 'dart:async';

import 'shift_backend.dart';

/// What runs when no server is configured — which is every build today, and
/// the public demo forever.
///
/// This is not a stub waiting to be replaced. Signing in is *optional*: the app
/// works unauthenticated on keys stored on the device, exactly as it does now,
/// and that has to keep being true after a server exists. Someone who never
/// makes an account should never meet a broken screen, and a hosting move
/// should never strand a signed-out user.
///
/// Reads return empty rather than throwing, because "you have no keys stored on
/// a server" is a true answer, not a failure. Writes throw
/// [BackendProblem.notConfigured], because silently accepting a key nobody
/// stored would be the worst possible outcome — the user would believe it was
/// saved.
class NoBackend implements ShiftBackend {
  final _sessions = StreamController<ShiftSession?>.broadcast();

  @override
  bool get isConfigured => false;

  @override
  ShiftSession? get session => null;

  @override
  Stream<ShiftSession?> get sessionChanges => _sessions.stream;

  @override
  Future<ShiftSession?> restore() async => null;

  @override
  Future<ShiftSession> signIn({
    required String email,
    required String password,
  }) async =>
      throw _unconfigured;

  @override
  Future<ShiftSession> signUp({
    required String email,
    required String password,
  }) async =>
      throw _unconfigured;

  @override
  Future<void> signOut() async {}

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) async =>
      throw _unconfigured;

  @override
  Future<void> deleteProviderKey(String id) async => throw _unconfigured;

  @override
  Future<Membership> membership() async => Membership.none;

  @override
  Future<Uri> billingPortal({String? plan}) async => throw _unconfigured;

  @override
  Future<List<ScheduledTask>> listScheduledTasks() async => const [];

  @override
  Future<ScheduledTask> saveScheduledTask(ScheduledTask task) async =>
      throw _unconfigured;

  @override
  Future<void> deleteScheduledTask(String id) async => throw _unconfigured;

  @override
  void dispose() => _sessions.close();

  static const _unconfigured = BackendException(
    BackendProblem.notConfigured,
    'This build has no server behind it. Keys and chats stay on this device.',
  );
}
