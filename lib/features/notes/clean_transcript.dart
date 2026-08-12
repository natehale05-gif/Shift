/// Turning what someone said into something they would have written.
///
/// The instruction is the whole feature. Dictation gives you the words; what
/// makes a note usable is losing the filler, gaining the punctuation, and
/// keeping every fact — and a model will happily "improve" a note into
/// something you did not say unless it is told not to, which is the failure
/// that would make people stop trusting the mode.
const String kCleanUpInstruction = '''
Rewrite this dictated text as the person would have written it.

Remove filler ("um", "uh", "like", "you know"), false starts and repeated
words. Add punctuation, capitalisation and paragraph breaks. Where the text is
clearly a list, set it as a list.

Do not add anything. Do not summarise, do not expand, do not add a heading that
was not spoken, and do not change any name, number, date or decision. If a
sentence is ambiguous, leave it ambiguous — rewriting it into something
definite is the one mistake that makes these notes untrustworthy.

Reply with the cleaned text and nothing else: no preamble, no explanation, no
code fence.''';

/// What the model gets: the instruction, then the words.
///
/// Separated by a marker rather than run together, so a dictation that happens
/// to contain instruction-like phrasing reads as content instead of as a second
/// instruction.
String cleanUpRequest(String spoken) =>
    '$kCleanUpInstruction\n\n--- dictated text ---\n${spoken.trim()}';

/// Undoes a model's habits when it ignores the last paragraph above.
///
/// Belt and braces, and cheap: a fenced reply or a "Here's the cleaned text:"
/// preamble would otherwise be written into the person's note verbatim.
String tidyCleanedReply(String reply) {
  var text = reply.trim();

  // A whole-reply code fence, which some models add to anything that looks
  // like a document.
  final fenced = RegExp(r'^```[a-zA-Z]*\n([\s\S]*?)\n?```$').firstMatch(text);
  if (fenced != null) text = fenced.group(1)!.trim();

  // A single-line preamble ending in a colon, but only when there is a blank
  // line after it — otherwise a genuine first line like "Shopping list:" would
  // be eaten, which is a real thing to dictate.
  final preamble = RegExp(
    r"^(here('| i)s|sure|certainly|okay|ok)\b[^\n]*:\s*\n\s*\n",
    caseSensitive: false,
  );
  text = text.replaceFirst(preamble, '');

  return text.trim();
}
