import 'package:flutter/foundation.dart';

import '../services/persistence_service.dart';
import '../services/providers/anthropic_client.dart';
import '../services/providers/gemini_client.dart';

enum KeyStatus { none, untested, testing, valid, invalid }

/// The user's own provider API keys (BYOK). Keys live only in this
/// browser's storage — there is no backend — and calls go browser-direct
/// to the provider. Adding a key flips chat from Simulated to Live;
/// removing it falls back to the mock.
class ApiKeysStore extends ChangeNotifier {
  static const _anthropicKeyName = 'shift_ai.anthropic_key.v1';
  static const _geminiKeyName = 'shift_ai.gemini_key.v1';

  final PersistenceService persistence;
  final AnthropicClient _anthropicClient;
  final GeminiClient _geminiClient;

  String _anthropicKey = '';
  String _geminiKey = '';
  KeyStatus _anthropicStatus = KeyStatus.none;
  KeyStatus _geminiStatus = KeyStatus.none;
  String? _anthropicError;
  String? _geminiError;

  ApiKeysStore({
    required this.persistence,
    AnthropicClient? anthropicClient,
    GeminiClient? geminiClient,
  })  : _anthropicClient = anthropicClient ?? AnthropicClient(),
        _geminiClient = geminiClient ?? GeminiClient();

  String get anthropicKey => _anthropicKey;
  String get geminiKey => _geminiKey;
  KeyStatus get anthropicStatus => _anthropicStatus;
  KeyStatus get geminiStatus => _geminiStatus;
  String? get anthropicError => _anthropicError;
  String? get geminiError => _geminiError;

  /// Live mode: any Anthropic key present (validation refines error
  /// reporting but doesn't gate sending).
  bool get hasAnthropicKey => _anthropicKey.isNotEmpty;
  bool get hasGeminiKey => _geminiKey.isNotEmpty;
  bool get isLive => hasAnthropicKey || hasGeminiKey;

  Future<void> load() async {
    _anthropicKey = await persistence.loadApiKey(_anthropicKeyName) ?? '';
    _geminiKey = await persistence.loadApiKey(_geminiKeyName) ?? '';
    _anthropicStatus =
        _anthropicKey.isEmpty ? KeyStatus.none : KeyStatus.untested;
    _geminiStatus = _geminiKey.isEmpty ? KeyStatus.none : KeyStatus.untested;
    notifyListeners();
  }

  Future<void> setAnthropicKey(String key) async {
    _anthropicKey = key.trim();
    _anthropicStatus =
        _anthropicKey.isEmpty ? KeyStatus.none : KeyStatus.untested;
    _anthropicError = null;
    notifyListeners();
    await persistence.saveApiKey(
        _anthropicKeyName, _anthropicKey.isEmpty ? null : _anthropicKey);
  }

  Future<void> setGeminiKey(String key) async {
    _geminiKey = key.trim();
    _geminiStatus = _geminiKey.isEmpty ? KeyStatus.none : KeyStatus.untested;
    _geminiError = null;
    notifyListeners();
    await persistence.saveApiKey(
        _geminiKeyName, _geminiKey.isEmpty ? null : _geminiKey);
  }

  Future<void> testGeminiKey() async {
    if (_geminiKey.isEmpty) return;
    _geminiStatus = KeyStatus.testing;
    _geminiError = null;
    notifyListeners();
    final problem = await _geminiClient.validateKey(_geminiKey);
    _geminiStatus = problem == null ? KeyStatus.valid : KeyStatus.invalid;
    _geminiError = problem;
    notifyListeners();
  }

  Future<void> testAnthropicKey() async {
    if (_anthropicKey.isEmpty) return;
    _anthropicStatus = KeyStatus.testing;
    _anthropicError = null;
    notifyListeners();
    final problem = await _anthropicClient.validateKey(_anthropicKey);
    _anthropicStatus = problem == null ? KeyStatus.valid : KeyStatus.invalid;
    _anthropicError = problem;
    notifyListeners();
  }
}
