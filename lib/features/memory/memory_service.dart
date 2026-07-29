/// Pulls durable, user-about facts out of a message so they can be remembered
/// across chats. Heuristic and deterministic (works in demo mode with no key);
/// conservative on purpose so it stores real facts, not passing chatter.
class MemoryService {
  MemoryService._();

  static final List<(RegExp, String Function(Match))> _patterns = [
    // Name / what to be called.
    (
      RegExp(r'\b(?:my name is|i am called|call me)\s+([A-Z][a-zA-Z]+)',
          caseSensitive: false),
      (m) => "User's name is ${_clean(m.group(1)!)}",
    ),
    // Location.
    (
      RegExp(r"\bi(?:'m| am)?\s+(?:from|based in|live in|located in)\s+"
          r'([A-Za-z][A-Za-z .,-]{1,40})', caseSensitive: false),
      (m) => 'Lives in ${_clause(m.group(1)!)}',
    ),
    // Job / role.
    (
      RegExp(r"\bi(?:'m| am)?\s+a\s+([a-z][a-z .-]{2,40}?)\s+"
          r'(?:by profession|by trade|for work)', caseSensitive: false),
      (m) => 'Works as a ${_clean(m.group(1)!)}',
    ),
    (
      RegExp(r'\b(?:i work as|my job is|i work in)\s+'
          r'([a-z][a-z .-]{2,40})', caseSensitive: false),
      (m) => 'Works as ${_clean(m.group(1)!)}',
    ),
    // Preferences.
    (
      RegExp(r'\bi\s+(?:really\s+)?(?:like|love|enjoy|prefer)\s+'
          r'([a-z][a-z0-9 .+-]{2,40})', caseSensitive: false),
      (m) => 'Likes ${_clause(m.group(1)!)}',
    ),
    (
      RegExp(r'\b(?:i use|i mostly use|i work with)\s+'
          r'([A-Za-z][A-Za-z0-9 .+#-]{1,40})', caseSensitive: false),
      (m) => 'Uses ${_clean(m.group(1)!)}',
    ),
    // Explicit "remember that ...".
    (
      RegExp(r'\bremember that\s+(.{4,80})', caseSensitive: false),
      (m) => _capitalize(_clean(m.group(1)!)),
    ),
  ];

  /// Extracts zero or more short facts from [message]. Deduplicated within the
  /// call; the store dedupes against what's already stored.
  static List<String> extractFacts(String message) {
    final facts = <String>[];
    final seen = <String>{};
    for (final (regex, build) in _patterns) {
      for (final match in regex.allMatches(message)) {
        final fact = build(match).trim();
        final key = fact.toLowerCase();
        if (fact.length >= 4 && seen.add(key)) facts.add(fact);
      }
    }
    return facts;
  }

  static String _clean(String s) =>
      s.trim().replaceAll(RegExp(r'[.,;:!?]+$'), '').trim();

  /// Trims a captured phrase at the first clause boundary (", and I …") so a
  /// run-on sentence doesn't get swallowed into one fact.
  static String _clause(String s) {
    final cut = s.split(RegExp(
      r'\s+(?:and|but|so|because|although|while|who|which)\s+|[,;]',
      caseSensitive: false,
    ));
    return _clean(cut.first);
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
