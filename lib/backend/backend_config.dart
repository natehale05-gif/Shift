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
/// The values default to the live project (see below), so an ordinary build is
/// configured. Passing an empty define deliberately turns the backend off and
/// the app runs on `NoBackend` — no account, keys on the device.
class BackendConfig {
  final String url;
  final String anonKey;

  const BackendConfig({required this.url, required this.anonKey});

  /// The project these values point at, committed rather than injected.
  ///
  /// This was a build-time secret-shaped thing for one release and it cost the
  /// whole feature: the repository variables were never set, so every deploy
  /// compiled `SHIFT_SUPABASE_URL=""`, the app fell back to `NoBackend`, and
  /// the account section hid itself — correctly, and invisibly. Sign-in simply
  /// was not on the site, and nothing said why. The release workflow never
  /// passed them at all, so every downloadable build had the same hole.
  ///
  /// They are safe to commit, and not as a compromise: the anon key is a token
  /// for the `anon` role, which `0006_lock_down_grants.sql` revokes *all*
  /// privileges from — it cannot read one row of one table. It is served to
  /// every visitor inside `main.dart.js` already, so a public repository adds
  /// discoverability and nothing else. What must never appear here is the
  /// service-role key, the master key, or the Stripe keys; those are on the
  /// server and stay there.
  ///
  /// Rotating the anon key is therefore a commit, which is the real cost of
  /// this choice and the reason the override below still exists.
  static const _defaultUrl = 'https://xmjaqizlrlsvjbwqmtdo.supabase.co';
  static const _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
      'InhtamFxaXpscmxzdmpid3FtdGRvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0Mjg0'
      'NzAsImV4cCI6MjEwMTAwNDQ3MH0.M0FML4ZDB0B7EOMBLAA1O5lMMzpWJbGAOwydTiZzSAk';

  /// A `--dart-define` still wins, so a staging project or a self-hosted stack
  /// is a build flag rather than a code change.
  static const _url =
      String.fromEnvironment('SHIFT_SUPABASE_URL', defaultValue: _defaultUrl);
  static const _anonKey = String.fromEnvironment('SHIFT_SUPABASE_ANON_KEY',
      defaultValue: _defaultAnonKey);

  /// Where the deployed app lives — the value the host's Site URL has to be
  /// set to, so a confirmation email lands somewhere real rather than on
  /// localhost.
  static const siteUrl = 'https://natehale05-gif.github.io/Shift/';

  /// The repository whose CI deploys the edge functions.
  static const repoUrl = 'https://github.com/natehale05-gif/Shift';

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
