/// Pure helpers for the Translate studio: pull the target language and the
/// source text out of a free-form request, build the LLM prompt, and provide a
/// clearly-labelled simulated fallback when no live provider is available.
class TranslateService {
  TranslateService._();

  /// Languages we recognise after a "to/into/in" cue. Kept broad but bounded so
  /// "translate this to me" doesn't read "me" as a language.
  static const _languages = [
    'spanish', 'french', 'german', 'italian', 'portuguese', 'dutch', 'russian',
    'polish', 'swedish', 'norwegian', 'danish', 'finnish', 'greek', 'turkish',
    'arabic', 'hebrew', 'hindi', 'bengali', 'urdu', 'persian', 'farsi',
    'japanese', 'korean', 'mandarin', 'cantonese', 'chinese', 'vietnamese',
    'thai', 'indonesian', 'malay', 'tagalog', 'filipino', 'swahili', 'zulu',
    'english', 'ukrainian', 'czech', 'romanian', 'hungarian', 'catalan',
    'welsh', 'irish', 'gaelic', 'latin', 'esperanto',
  ];

  /// The target language named in [input] (e.g. "translate this to Spanish"),
  /// canonicalised (Title Case), or null when none is found.
  static String? parseTargetLanguage(String input) {
    final lower = input.toLowerCase();
    // Prefer an explicit "to/into/in <language>" cue.
    final cue = RegExp(r'\b(?:to|into|in)\s+([a-z]+)').allMatches(lower);
    for (final m in cue) {
      final word = m.group(1)!;
      if (_languages.contains(word)) return _title(word);
    }
    // Otherwise any bare language mention.
    for (final lang in _languages) {
      if (RegExp('\\b$lang\\b').hasMatch(lower)) return _title(lang);
    }
    return null;
  }

  /// The text to translate, with the command wrapper and language clause
  /// stripped. If the request has a ':' (e.g. "translate to French: hello"),
  /// everything after the first ':' is taken verbatim.
  static String extractSourceText(String input) {
    final colon = input.indexOf(':');
    if (colon != -1 && colon < input.length - 1) {
      return input.substring(colon + 1).trim();
    }
    var s = input;
    // Strip a leading command phrase.
    s = s.replaceFirst(
        RegExp(
            r'^\s*(please\s+)?(can|could|would)?\s*(you\s+)?'
            r'(please\s+)?translate(\s+this|\s+the\s+following|\s+it)?\s*',
            caseSensitive: false),
        '');
    // Strip a trailing / leading "to|into|in <language>" clause.
    final lang = parseTargetLanguage(input);
    if (lang != null) {
      s = s.replaceAll(
          RegExp('\\b(to|into|in)\\s+${lang.toLowerCase()}\\b',
              caseSensitive: false),
          '');
    }
    return s.trim();
  }

  /// The instruction handed to the best available text provider.
  static String translationPrompt(String source, String targetLanguage) =>
      'Translate the following text into $targetLanguage. Output ONLY the '
      'translation — no preamble, no notes, no quotes — and preserve line '
      'breaks and basic formatting.\n\n$source';

  /// Honest placeholder used when there is no live text provider: the app
  /// cannot actually translate offline, so this makes that explicit.
  static String simulatedTranslation(String source, String targetLanguage) =>
      '[Simulated $targetLanguage translation — add an API key in Settings for '
      'a real translation.]\n\n$source';

  static String _title(String word) =>
      word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);
}
