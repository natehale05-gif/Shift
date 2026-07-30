/// How a request becomes a short human label for what it produced.
///
/// One rule, three consumers: both backends naming an artifact, and the
/// conversation store naming a chat. All three used to do it themselves and
/// all three did it differently — demo mode used the raw prompt ("build me a
/// landing page for my bakery"), the live path used the constant "Generated
/// page" for everything, and a conversation was the first message chopped at
/// 40 characters.
///
/// For artifacts this is not decoration: the title becomes the download
/// filename via `DownloadService.slugify`, which keeps only the first six
/// words, so the prompt version lost its subject and the live version collided
/// with every other download.
///
/// Lives in `turn/` rather than with the artifact code because `data/` needs it
/// too and `data/` does not import `features/`.
library;

/// Politeness and request framing that carries no information about the thing
/// being made. Stripped from the front, repeatedly, so stacked openers like
/// "please can you build me a …" reduce all the way down.
final _preamble = RegExp(
  r'^\s*(?:'
  r'please|hey|hi|ok(?:ay)?|so|now|'
  r'can you|could you|would you|will you|i(?:\s+would like|\s*d like|\s+want|\s+need)'
  r'(?:\s+you)?(?:\s+to)?|'
  r"lets|let's|"
  r'build|create|make|write|design|generate|give|draft|put together|whip up|'
  r'me|us|for me|'
  r'a|an|the|my|our|some'
  r')\b[\s,:-]*',
  caseSensitive: false,
);

/// Trailing politeness and punctuation.
final _trailing = RegExp(
  r'[\s,.!?;:-]*(?:\bplease\b|\bthanks\b|\bthank you\b)?[\s,.!?;:-]*$',
  caseSensitive: false,
);

const _maxWords = 8;
const _maxChars = 60;

/// A short human title for the artifact [userInput] produces.
///
/// Pure: the same request always names the same thing, whichever backend runs
/// it. Casing after the first letter is left exactly as typed, so "SaaS",
/// "iOS" and proper nouns survive.
String titleFromRequest(String userInput, {String fallback = 'Untitled page'}) {
  var text = userInput.trim();

  // Peel openers one at a time — "build me a landing page" needs three passes
  // ("build", "me", "a") and stacked politeness needs more.
  var previous = '';
  while (text != previous) {
    previous = text;
    text = text.replaceFirst(_preamble, '');
  }

  text = text.replaceFirst(_trailing, '').trim();
  if (text.isEmpty) return fallback;

  // Cap on a word boundary, comfortably under slugify's six-word cut so the
  // filename keeps the subject rather than trailing off mid-phrase.
  var words = text.split(RegExp(r'\s+'));
  if (words.length > _maxWords) words = words.sublist(0, _maxWords);
  var title = words.join(' ');
  while (title.length > _maxChars && words.length > 1) {
    words = words.sublist(0, words.length - 1);
    title = words.join(' ');
  }
  if (title.length > _maxChars) title = title.substring(0, _maxChars).trim();
  if (title.isEmpty) return fallback;

  return title[0].toUpperCase() + title.substring(1);
}

/// A title read out of what was actually built, falling back to the request.
///
/// The request is a poor name for the thing it asked for: "build me a landing
/// page for my bakery" names the *errand*, not the deliverable, and two pages
/// for the same bakery get near-identical names. The finished page already
/// carries a better one — its `<title>`, or its headline — chosen by whoever
/// wrote it with the whole page in view.
///
/// Pure, so the rule is the same in both backends and testable without
/// generating anything.
String titleFromArtifact(
  String content, {
  String? language,
  required String request,
}) {
  final fromContent = _htmlTitle(content) ?? _codeTitle(content, language);
  if (fromContent != null) return fromContent;
  return titleFromRequest(request);
}

/// `<title>` first, then the first `<h1>` — a page's own name for itself.
String? _htmlTitle(String content) {
  for (final pattern in [
    RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false),
    RegExp(r'<h1[^>]*>([\s\S]*?)</h1>', caseSensitive: false),
  ]) {
    final match = pattern.firstMatch(content);
    if (match == null) continue;
    // Strip any nested markup — a headline is often wrapped in a span.
    final text = match
        .group(1)!
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_usable(text)) return _cap(text);
  }
  return null;
}

/// For code: the thing it declares. A component called `PricingTable` is a
/// better name than the sentence that asked for one.
String? _codeTitle(String content, String? language) {
  final match = RegExp(
    r'\b(?:export\s+default\s+)?(?:class|function|const|def|struct|interface)'
    r'\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(content);
  final name = match?.group(1);
  if (name == null || name.length < 3) return null;
  if (const {'main', 'app', 'index', 'test', 'init'}.contains(name.toLowerCase())) {
    return null;
  }
  // CamelCase and snake_case both become words.
  final words = name
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
      .trim();
  final suffix = language == null || language.isEmpty ? '' : ' ($language)';
  return '${_cap(words)}$suffix';
}

/// Rejects the names that are worse than the request: boilerplate a template
/// left behind, and anything too long or too short to read as a name.
bool _usable(String text) {
  if (text.length < 3 || text.length > 60) return false;
  const boilerplate = {
    'document', 'untitled', 'untitled document', 'title', 'page', 'home',
    'index', 'my website', 'website', 'hello world', 'new document',
  };
  return !boilerplate.contains(text.toLowerCase());
}

String _cap(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
