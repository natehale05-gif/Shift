import '../turn/capability.dart';

/// One model a provider offers.
class ProviderModel {
  final String id;
  final String displayName;

  /// What this specific model can do. A provider's own set is the union of its
  /// models', but a step needs a *model*, not a company — asking Gemini for an
  /// image and getting `gemini-2.5-pro` is a 400 that reads like a bug.
  final Set<Capability> can;

  const ProviderModel({
    required this.id,
    required this.displayName,
    required this.can,
  });
}

/// A provider, and what it is good for.
class ProviderDescriptor {
  final String id;
  final String displayName;

  /// Where the user gets a key, shown beside the field. Small thing; it is the
  /// difference between pasting a key in a minute and giving up.
  final Uri keyUrl;

  /// A key that does not match this is rejected before any request is sent —
  /// a typo should cost nothing and say so immediately, rather than becoming a
  /// 401 the user reads as "my key is wrong" when it was truncated on paste.
  final RegExp? keyShape;

  final List<ProviderModel> models;

  /// Lower wins. Absent means this provider is not a candidate for that
  /// capability at all, which is different from being a poor one.
  final Map<Capability, int> ranks;

  /// For the providers that speak OpenAI's `chat/completions`, where the only
  /// thing that differs between them is this string. Null for the ones with
  /// their own wire — a field that means "the OpenAI-compatible base URL"
  /// should be absent rather than pointing somewhere plausible and wrong.
  final String? baseUrl;

  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.keyUrl,
    required this.models,
    required this.ranks,
    this.keyShape,
    this.baseUrl,
  });

  Set<Capability> get can => {for (final m in models) ...m.can};

  /// The best model here for [capability], or null if there is none.
  ProviderModel? modelFor(Capability capability) {
    for (final model in models) {
      if (model.can.contains(capability)) return model;
    }
    return null;
  }
}

/// The providers this app knows how to talk to.
///
/// **One vocabulary.** v1 had `ProviderCapability` *and* `ChatRoute`, bridged
/// by `capabilityForRoute`, because routing was built before capabilities
/// were. A step in v2 already carries a [Capability], so the table is keyed on
/// the same value the step holds and the bridge is deleted rather than ported.
/// The bridge was not merely redundant — it was where a provider could be
/// capable of something the router had no route to, which is exactly the gap
/// that left Gemini unable to build a page in v1 for months.
/// Not `const`: the descriptors hold parsed [Uri]s and [RegExp]s, neither of
/// which is a constant expression. Keeping the URL and the key shape *on the
/// descriptor* is worth that — the alternative is a second table somewhere
/// else that has to be kept in step with this one.
final List<ProviderDescriptor> kProviders = [
  _anthropic,
  _gemini,
  _openai,
  _groq,
  _mistral,
  _openrouter,
];

ProviderDescriptor? providerById(String id) {
  for (final p in kProviders) {
    if (p.id == id) return p;
  }
  return null;
}

// Text ranks are the interesting ones and they are ordered on quality of
// written output, which is what "which model should answer this" means in an
// app whose default mode is a conversation.

final _anthropic = ProviderDescriptor(
  id: 'anthropic',
  displayName: 'Claude',
  keyUrl: Uri.parse('https://console.anthropic.com/settings/keys'),
  keyShape: RegExp(r'^sk-ant-'),
  models: const [
    ProviderModel(
      id: 'claude-opus-4-8',
      displayName: 'Claude Opus 4.8',
      can: {Capability.text, Capability.search},
    ),
    ProviderModel(
      id: 'claude-sonnet-5',
      displayName: 'Claude Sonnet 5',
      can: {Capability.text, Capability.search},
    ),
    ProviderModel(
      id: 'claude-haiku-4-5',
      displayName: 'Claude Haiku 4.5',
      can: {Capability.text},
    ),
  ],
  ranks: const {Capability.text: 0, Capability.search: 0},
);

final _gemini = ProviderDescriptor(
  id: 'gemini',
  displayName: 'Gemini',
  keyUrl: Uri.parse('https://aistudio.google.com/apikey'),
  models: const [
    ProviderModel(
      id: 'gemini-2.5-flash',
      displayName: 'Gemini 2.5 Flash',
      can: {Capability.text, Capability.search},
    ),
    ProviderModel(
      id: 'gemini-2.5-pro',
      displayName: 'Gemini 2.5 Pro',
      can: {Capability.text},
    ),
    ProviderModel(
      id: 'gemini-2.5-flash-image',
      displayName: 'Gemini 2.5 Flash Image',
      can: {Capability.image},
    ),
  ],
  // Leads on image, second on text.
  ranks: const {Capability.text: 2, Capability.image: 0, Capability.search: 1},
);

final _openai = ProviderDescriptor(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  keyUrl: Uri.parse('https://platform.openai.com/api-keys'),
  keyShape: RegExp(r'^sk-'),
  models: const [
    ProviderModel(
      id: 'gpt-4o',
      displayName: 'GPT-4o',
      can: {Capability.text},
    ),
    ProviderModel(
      id: 'gpt-image-1',
      displayName: 'GPT Image 1',
      can: {Capability.image},
    ),
  ],
  ranks: const {Capability.text: 1, Capability.image: 1},
);

final _groq = ProviderDescriptor(
  id: 'groq',
  displayName: 'Groq',
  baseUrl: 'https://api.groq.com/openai/v1',
  keyUrl: Uri.parse('https://console.groq.com/keys'),
  keyShape: RegExp(r'^gsk_'),
  models: const [
    ProviderModel(
      id: 'llama-3.3-70b-versatile',
      displayName: 'Llama 3.3 70B',
      can: {Capability.text},
    ),
  ],
  ranks: const {Capability.text: 3},
);

final _mistral = ProviderDescriptor(
  id: 'mistral',
  displayName: 'Mistral',
  baseUrl: 'https://api.mistral.ai/v1',
  keyUrl: Uri.parse('https://console.mistral.ai/api-keys'),
  models: const [
    ProviderModel(
      id: 'mistral-large-latest',
      displayName: 'Mistral Large',
      can: {Capability.text},
    ),
  ],
  ranks: const {Capability.text: 4},
);

final _openrouter = ProviderDescriptor(
  id: 'openrouter',
  displayName: 'OpenRouter',
  baseUrl: 'https://openrouter.ai/api/v1',
  keyUrl: Uri.parse('https://openrouter.ai/keys'),
  keyShape: RegExp(r'^sk-or-'),
  models: const [
    ProviderModel(
      id: 'anthropic/claude-sonnet-5',
      displayName: 'Claude Sonnet 5 (OpenRouter)',
      can: {Capability.text},
    ),
  ],
  ranks: const {Capability.text: 5},
);
