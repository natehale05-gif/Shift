import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config.dart';
import 'shift_backend.dart';

/// [ShiftBackend] over Supabase, spoken to as **plain HTTP** rather than
/// through `supabase_flutter`.
///
/// Two reasons, both of which were the point of the wave:
///
/// *Portability.* The endpoints below are GoTrue and PostgREST, not Supabase
/// inventions. The same paths answer on a self-hosted stack, and moving to a
/// different one is a subclass overriding a handful of URLs rather than tearing
/// out an SDK that has grown into the widget tree.
///
/// *Payload.* This app already ships ~12.5 MB before any of its own code, and
/// the one thing the whole R-series could not fix was first-load weight. A
/// vendor SDK for what amounts to a dozen REST calls is the wrong trade; the
/// realtime and storage features it also brings are not used.
///
/// The session is held in memory and handed back to the caller to persist —
/// this class does no I/O beyond HTTP, which is what makes it testable against
/// a fake client with no store, no files and no browser.
class SupabaseBackend implements ShiftBackend {
  final BackendConfig config;
  final http.Client _http;

  /// Called whenever the session changes, so the caller can persist it. Kept as
  /// a callback rather than a store dependency: this class knowing how the app
  /// stores things is the coupling that makes a backend hard to replace.
  final Future<void> Function(ShiftSession?)? onSessionChanged;

  /// Loads whatever [onSessionChanged] last saved. Null on a fresh install.
  final Future<ShiftSession?> Function()? loadStoredSession;

  ShiftSession? _session;
  final _sessions = StreamController<ShiftSession?>.broadcast();

  SupabaseBackend({
    required this.config,
    http.Client? client,
    this.onSessionChanged,
    this.loadStoredSession,
  }) : _http = client ?? http.Client();

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => _session;

  @override
  Stream<ShiftSession?> get sessionChanges => _sessions.stream;

  // ---------------------------------------------------------------- sessions

  @override
  Future<ShiftSession?> restore() async {
    final stored = await loadStoredSession?.call();
    if (stored == null) return null;
    if (!stored.isExpired) return _adopt(stored);

    final refresh = stored.refreshToken;
    if (refresh == null) return null;
    try {
      return _adopt(await _token({'refresh_token': refresh}, 'refresh_token'));
    } on BackendException {
      // A refresh token that no longer works means signed out, not broken.
      // Throwing here would greet someone with an error on launch for the
      // ordinary reason that they had not opened the app in a while.
      await _clear();
      return null;
    }
  }

  @override
  Future<ShiftSession> signIn({
    required String email,
    required String password,
  }) async =>
      _adopt(await _token(
        {'email': email, 'password': password},
        'password',
      ));

  @override
  Future<ShiftSession> signUp({
    required String email,
    required String password,
  }) async {
    final body = await _post(
      Uri.parse('${config.url}/auth/v1/signup'),
      {'email': email, 'password': password},
      authorized: false,
    );
    final parsed = _sessionFrom(body);
    if (parsed == null) {
      // Projects with email confirmation on return a user and no token. That
      // is a success, not a failure, and the caller has to be told which it
      // was — so it is an exception carrying the reason rather than a null.
      throw const BackendException(BackendProblem.credentials,
          'Check your email to confirm the account, then sign in.');
    }
    return _adopt(parsed);
  }

  @override
  Future<void> signOut() async {
    final token = _session?.accessToken;
    if (token != null) {
      // Best effort. If the server never hears about it the token still
      // expires, and refusing to sign out locally because a request failed
      // would strand someone signed in on a device they wanted to leave.
      try {
        await _http.post(
          Uri.parse('${config.url}/auth/v1/logout'),
          headers: _headers(token: token),
        );
      } catch (_) {}
    }
    await _clear();
  }

  Future<ShiftSession> _token(
      Map<String, String> body, String grantType) async {
    final json = await _post(
      Uri.parse('${config.url}/auth/v1/token?grant_type=$grantType'),
      body,
      authorized: false,
    );
    final parsed = _sessionFrom(json);
    if (parsed == null) {
      throw const BackendException(
          BackendProblem.credentials, 'That email and password did not match.');
    }
    return parsed;
  }

  ShiftSession? _sessionFrom(Map<String, dynamic> json) {
    final token = json['access_token'] as String?;
    final user = json['user'] as Map<String, dynamic>?;
    final id = user?['id'] as String?;
    if (token == null || id == null) return null;

    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return ShiftSession(
      account: ShiftAccount(
        id: id,
        email: user?['email'] as String?,
        displayName:
            (user?['user_metadata'] as Map<String, dynamic>?)?['name'] as String?,
      ),
      accessToken: token,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  ShiftSession _adopt(ShiftSession next) {
    _session = next;
    _sessions.add(next);
    onSessionChanged?.call(next);
    return next;
  }

  Future<void> _clear() async {
    _session = null;
    _sessions.add(null);
    await onSessionChanged?.call(null);
  }

  /// The token to send, refreshed first if it is about to expire.
  ///
  /// Every authorized call goes through here rather than reading `_session`
  /// directly, so a long-running app cannot start failing silently once its
  /// hour is up.
  Future<String> _freshToken() async {
    final current = _session;
    if (current == null) {
      throw const BackendException(
          BackendProblem.notSignedIn, 'Sign in to use this.');
    }
    if (!current.isExpired) return current.accessToken;

    final refresh = current.refreshToken;
    if (refresh == null) {
      await _clear();
      throw const BackendException(
          BackendProblem.notSignedIn, 'Your session expired. Sign in again.');
    }
    final renewed = _adopt(await _token({'refresh_token': refresh}, 'refresh_token'));
    return renewed.accessToken;
  }

  // ------------------------------------------------------------ key vault

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async {
    final rows = await _get(
      Uri.parse('${config.url}/rest/v1/provider_key_metadata'
          '?select=id,provider,key_owner,last_four,created_at'),
    );
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>)
          ProviderKeyInfo(
            id: row['id'] as String? ?? '',
            provider: row['provider'] as String? ?? '',
            lastFour: row['last_four'] as String? ?? '',
            managed: row['key_owner'] == 'managed',
            addedAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
          ),
    ];
  }

  @override
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) async {
    // Through an edge function, never straight into the table: the row holds
    // ciphertext, and the key that encrypts it is not something a client is
    // allowed to hold.
    final json = await _post(
      Uri.parse('${config.url}/functions/v1/provider-key'),
      {'provider': provider, 'secret': secret},
    );
    return ProviderKeyInfo(
      id: json['id'] as String? ?? '',
      provider: provider,
      lastFour: json['last_four'] as String? ?? '',
      managed: false,
      addedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteProviderKey(String id) => _delete(
        Uri.parse('${config.url}/rest/v1/provider_keys?id=eq.$id'),
      );

  // ----------------------------------------------------------- membership

  @override
  Future<Membership> membership() async {
    final rows = await _get(
      Uri.parse('${config.url}/rest/v1/subscriptions'
          '?select=status,plan,current_period_end,spend_ceiling_micros'),
    );
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
      // No row is a real state, not an error: it is what someone using their
      // own keys has.
      return Membership.none;
    }
    final row = rows.first as Map<String, dynamic>;

    final usage = await _get(
      Uri.parse('${config.url}/rest/v1/rpc/managed_spend_micros'),
      allowFailure: true,
    );

    return Membership(
      status: _statusFrom(row['status'] as String?),
      plan: row['plan'] as String?,
      renewsAt: DateTime.tryParse(row['current_period_end'] as String? ?? ''),
      ceilingMicros: (row['spend_ceiling_micros'] as num?)?.toInt() ?? 0,
      spentMicros: usage.isEmpty ? 0 : (usage.first as num?)?.toInt() ?? 0,
    );
  }

  static MembershipStatus _statusFrom(String? value) => switch (value) {
        'trialing' => MembershipStatus.trialing,
        'active' => MembershipStatus.active,
        'past_due' => MembershipStatus.pastDue,
        'canceled' => MembershipStatus.canceled,
        _ => MembershipStatus.none,
      };

  @override
  Future<Uri> billingPortal({String? plan}) async {
    final json = await _post(
      Uri.parse('${config.url}/functions/v1/billing-portal'),
      {if (plan != null) 'plan': plan},
    );
    final url = json['url'] as String?;
    if (url == null) {
      throw const BackendException(
          BackendProblem.unavailable, 'Billing is unavailable right now.');
    }
    return Uri.parse(url);
  }

  // ------------------------------------------------------ scheduled tasks

  @override
  Future<List<ScheduledTask>> listScheduledTasks() async {
    final rows = await _get(
      Uri.parse('${config.url}/rest/v1/scheduled_tasks'
          '?select=*&order=created_at.desc'),
    );
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) _taskFrom(row),
    ];
  }

  @override
  Future<ScheduledTask> saveScheduledTask(ScheduledTask task) async {
    final ownerId = (await _freshTokenOwner());
    final body = {
      if (task.id.isNotEmpty) 'id': task.id,
      'owner_id': ownerId,
      'name': task.name,
      'cron': task.cron,
      'prompt': task.prompt,
      'enabled': task.enabled,
    };
    final rows = await _postRows(
      Uri.parse('${config.url}/rest/v1/scheduled_tasks'
          '?on_conflict=id&select=*'),
      body,
      prefer: 'resolution=merge-duplicates,return=representation',
    );
    if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
      throw const BackendException(
          BackendProblem.unavailable, 'The schedule could not be saved.');
    }
    return _taskFrom(rows.first as Map<String, dynamic>);
  }

  @override
  Future<void> deleteScheduledTask(String id) => _delete(
        Uri.parse('${config.url}/rest/v1/scheduled_tasks?id=eq.$id'),
      );

  Future<String> _freshTokenOwner() async {
    await _freshToken();
    final id = _session?.account.id;
    if (id == null) {
      throw const BackendException(
          BackendProblem.notSignedIn, 'Sign in to use this.');
    }
    return id;
  }

  static ScheduledTask _taskFrom(Map<String, dynamic> row) => ScheduledTask(
        id: row['id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        cron: row['cron'] as String? ?? '',
        prompt: row['prompt'] as String? ?? '',
        enabled: row['enabled'] as bool? ?? true,
        lastRunAt: DateTime.tryParse(row['last_run_at'] as String? ?? ''),
        nextRunAt: DateTime.tryParse(row['next_run_at'] as String? ?? ''),
      );

  // ----------------------------------------------------------------- HTTP

  Map<String, String> _headers({String? token, String? prefer}) => {
        'apikey': config.anonKey,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (prefer != null) 'Prefer': prefer,
      };

  Future<List<dynamic>> _get(Uri uri, {bool allowFailure = false}) async {
    try {
      final response =
          await _http.get(uri, headers: _headers(token: await _freshToken()));
      if (response.statusCode >= 400) {
        if (allowFailure) return const [];
        throw _problemFor(response);
      }
      final decoded = jsonDecode(response.body);
      return decoded is List ? decoded : [decoded];
    } on BackendException {
      if (allowFailure) return const [];
      rethrow;
    } catch (e) {
      if (allowFailure) return const [];
      throw _offline(e);
    }
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> body, {
    bool authorized = true,
  }) async {
    final response = await _send(
      () async => _http.post(
        uri,
        headers: _headers(token: authorized ? await _freshToken() : null),
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode >= 400) throw _problemFor(response);
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<List<dynamic>> _postRows(
    Uri uri,
    Map<String, dynamic> body, {
    required String prefer,
  }) async {
    final response = await _send(
      () async => _http.post(
        uri,
        headers: _headers(token: await _freshToken(), prefer: prefer),
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode >= 400) throw _problemFor(response);
    final decoded = jsonDecode(response.body);
    return decoded is List ? decoded : [decoded];
  }

  Future<void> _delete(Uri uri) async {
    final response = await _send(
      () async => _http.delete(uri, headers: _headers(token: await _freshToken())),
    );
    if (response.statusCode >= 400) throw _problemFor(response);
  }

  /// Runs a request, turning anything that is not an HTTP answer — offline, DNS
  /// failure, a timeout — into [BackendProblem.unavailable]. A raw SocketException
  /// escaping into a button handler is how an app shows a red screen for "the
  /// wifi dropped".
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on BackendException {
      rethrow;
    } catch (e) {
      throw _offline(e);
    }
  }

  /// A request that never reached an HTTP answer — offline, DNS, a blocked
  /// proxy, a timeout.
  ///
  /// The exception text goes in `detail`, which is for logs. Putting it in
  /// `message` is how a sign-in form ended up displaying
  /// `ClientException: Failed to fetch, uri=https://…/auth/v1/token`: useless
  /// to the person who typed a password, and it prints the project's address
  /// to anyone looking at the screen.
  BackendException _offline(Object error) => BackendException(
        BackendProblem.unavailable,
        defaultMessageFor(BackendProblem.unavailable),
        detail: '$error',
      );

  BackendException _problemFor(http.Response response) {
    final problem = switch (response.statusCode) {
      400 || 401 || 422 => BackendProblem.credentials,
      403 => BackendProblem.notSignedIn,
      402 || 429 => BackendProblem.overLimit,
      _ => BackendProblem.unavailable,
    };
    // The server's own wording is better than anything invented here, when it
    // bothers to send one; otherwise the problem's own sentence, which at
    // least says what to do. A bare status code says neither.
    String message = defaultMessageFor(problem);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        message = (decoded['message'] ??
                decoded['error_description'] ??
                decoded['msg'] ??
                decoded['error'] ??
                message)
            .toString();
      }
    } catch (_) {}
    return BackendException(problem, message,
        detail: 'HTTP ${response.statusCode}');
  }

  @override
  void dispose() {
    _sessions.close();
    _http.close();
  }
}
