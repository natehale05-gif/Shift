/// Where the backend lives, read at compile time.
///
/// Both values are public by design — the project URL and the anon key are
/// meant to ship in the client, and row security is what protects the data, not
/// the secrecy of these. The service-role key, the KMS key id and the Stripe
/// keys are *not* here and must never be: they would be readable by anyone who
/// downloaded the app.
///
///   flutter build web --dart-define=SHIFT_SUPABASE_URL=https://xyz.supabase.co \
///                     --dart-define=SHIFT_SUPABASE_ANON_KEY=eyJ...
///
/// Absent, the app runs on [NoBackend] — no account, keys on the device, which
/// is what the public demo does and what every build does today.
class BackendConfig {
  final String url;
  final String anonKey;

  const BackendConfig({required this.url, required this.anonKey});

  static const _url = String.fromEnvironment('SHIFT_SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SHIFT_SUPABASE_ANON_KEY');

  /// The configuration this build was compiled with, or null when it has none.
  ///
  /// Requires *both* values. A URL without a key would produce a client that
  /// looks configured and fails every call, which is worse than one that
  /// honestly has no server.
  static BackendConfig? fromEnvironment() {
    if (_url.isEmpty || _anonKey.isEmpty) return null;
    return const BackendConfig(url: _url, anonKey: _anonKey);
  }
}
