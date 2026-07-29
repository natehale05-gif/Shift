/// How a request becomes the name of the thing it produces.
///
/// Shared by both backends deliberately. They used to name artifacts
/// independently and both got it wrong: demo mode used the raw prompt ("build
/// me a landing page for my bakery"), and the live path used the constant
/// "Generated page" for everything. Titles are not decoration — they become the
/// download filename via `DownloadService.slugify`, which keeps only the first
/// six words, so the prompt version lost its subject and the live version
/// collided with every other download.
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
String artifactTitleFor(String userInput, {String fallback = 'Untitled page'}) {
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
