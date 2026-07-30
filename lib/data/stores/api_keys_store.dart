import 'package:flutter/foundation.dart';

import '../persistence/persistence_service.dart';
import '../../providers/clients/provider_registry.dart';

enum KeyStatus { none, untested, testing, valid, invalid }

/// The user's own provider API keys (BYOK), keyed by provider id. Keys live
/// only in this browser's storage — there is no backend — and calls go
/// browser-direct to the provider. Adding any key flips chat from Simulated to
/// Live; removing the last one falls back to the mock.
///
/// The store is map-backed and driven off [ProviderRegistry], so a new
/// provider needs no changes here. The Anthropic/Gemini-specific getters and
/// setters are thin shims over the generic API, kept for the many existing
/// callers and tests.
class ApiKeysStore extends ChangeNotifier {
  final PersistenceService persistence;
  final ProviderRegistry registry;
  final ClientRegistry _clients;

  final Map<String, String> _keys = {};
  final Map<String, KeyStatus> _status = {};
  final Map<String, String?> _errors = {};

  ApiKeysStore({
    required this.persistence,
    ProviderRegistry? registry,
    ClientRegistry? clients,
  })  : registry = registry ?? ProviderRegistry.defaults(),
        _clients = clients ?? ClientRegistry();

  // ---- Generic, registry-driven API ----

  /// The stored key for [providerId], or '' when none.
  String keyFor(String providerId) => _keys[providerId] ?? '';

  /// Whether a (non-empty) key is present for [providerId].
  bool hasKey(String providerId) => keyFor(providerId).isNotEmpty;

  KeyStatus statusFor(String providerId) =>
      _status[providerId] ?? KeyStatus.none;

  String? errorFor(String providerId) => _errors[providerId];

  /// Live mode: any provider key present (validation refines error reporting
  /// but doesn't gate sending).
  bool get isLive => registry.all.any((d) => hasKey(d.id));

  /// Loads every registered provider's key from persistence.
  Future<void> load() async {
    for (final descriptor in registry.all) {
      // Sanitised on the way in as well as the way out: a key saved by an
      // earlier build kept whatever whitespace was pasted into it, and would
      // otherwise keep failing after this fix shipped.
      final key = sanitizeKey(
          await persistence.loadApiKey(descriptor.persistenceKeyName) ?? '');
      _keys[descriptor.id] = key;
      _status[descriptor.id] =
          key.isEmpty ? KeyStatus.none : KeyStatus.untested;
    }
    notifyListeners();
  }

  /// Strips every whitespace character from a pasted key.
  ///
  /// No provider issues keys containing whitespace, so removing it can only
  /// help — and pasted keys arrive with it constantly: wrapped in an email,
  /// copied off a phone, broken across lines by a terminal. `trim()` alone
  /// cleans the ends and leaves newlines in the middle, which then travel
  /// into the `x-api-key` header and come back 401. The app then blames the
  /// key, which is the one explanation that sends people looking in the wrong
  /// place.
  static String sanitizeKey(String key) => key.replaceAll(RegExp(r'\s'), '');

  /// Sets (or, when empty, clears) the key for [providerId] and persists it.
  Future<void> setKey(String providerId, String key) async {
    final descriptor = registry.byId(providerId);
    if (descriptor == null) return;
    final value = sanitizeKey(key);
    _keys[providerId] = value;
    _status[providerId] = value.isEmpty ? KeyStatus.none : KeyStatus.untested;
    _errors[providerId] = null;
    notifyListeners();
    await persistence.saveApiKey(
        descriptor.persistenceKeyName, value.isEmpty ? null : value);
  }

  /// Validates the stored key for [providerId] against its provider client.
  Future<void> testKey(String providerId) async {
    final descriptor = registry.byId(providerId);
    if (descriptor == null) return;
    final value = keyFor(providerId);
    if (value.isEmpty) return;
    _status[providerId] = KeyStatus.testing;
    _errors[providerId] = null;
    notifyListeners();
    final problem = await _clients.validateKey(descriptor, value);
    _status[providerId] =
        problem == null ? KeyStatus.valid : KeyStatus.invalid;
    _errors[providerId] = problem;
    notifyListeners();
  }

  // ---- Legacy Anthropic/Gemini shims (delegate to the generic API) ----

  String get anthropicKey => keyFor('anthropic');
  String get geminiKey => keyFor('gemini');
  KeyStatus get anthropicStatus => statusFor('anthropic');
  KeyStatus get geminiStatus => statusFor('gemini');
  String? get anthropicError => errorFor('anthropic');
  String? get geminiError => errorFor('gemini');

  bool get hasAnthropicKey => hasKey('anthropic');
  bool get hasGeminiKey => hasKey('gemini');

  Future<void> setAnthropicKey(String key) => setKey('anthropic', key);
  Future<void> setGeminiKey(String key) => setKey('gemini', key);
  Future<void> testAnthropicKey() => testKey('anthropic');
  Future<void> testGeminiKey() => testKey('gemini');
}
