import 'dart:convert';

/// A question the model wants to ask with tappable answers.
class OfferedChoice {
  final String question;
  final List<String> options;
  final bool multiSelect;
  const OfferedChoice({
    required this.question,
    required this.options,
    this.multiSelect = false,
  });
}

/// The fence tag the model is told to use.
const String choiceFenceTag = 'shift:choices';

/// The most a question may offer.
///
/// Past this it stops being a decision and becomes a list to read, at which
/// point prose is better and typing is faster. Anything longer is rejected
/// rather than truncated — silently dropping options would ask the user to
/// choose from a set that is missing the one they wanted.
const int maxChoiceOptions = 6;

/// Reads a ```shift:choices block, or null when there is nothing usable.
///
/// Null on every kind of malformation, because the reply that carried it is
/// still perfectly good prose. A question rendered with no options, or with
/// one, is worse than no question at all — the user is shown a decision they
/// cannot make.
OfferedChoice? parseChoiceBlock(String source) {
  final decoded = _decode(source);
  if (decoded == null) return null;

  final question = (decoded['question'] as String?)?.trim() ?? '';
  if (question.isEmpty) return null;

  final raw = decoded['options'];
  if (raw is! List) return null;
  final options = [
    for (final option in raw)
      if (option is String && option.trim().isNotEmpty) option.trim(),
  ];
  // Two is the fewest that is a choice. One option is an instruction.
  if (options.length < 2 || options.length > maxChoiceOptions) return null;
  if (options.toSet().length != options.length) return null;

  return OfferedChoice(
    question: question,
    options: options,
    multiSelect: decoded['multiSelect'] as bool? ?? false,
  );
}

Map<String, dynamic>? _decode(String source) {
  try {
    final value = jsonDecode(source.trim());
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// Appended to the system prompt so the model knows the option exists.
///
/// Deliberately narrow. A model that offers choices for everything turns every
/// answer into a form; the value is in the cases where the decision is
/// genuinely the user's and the answer set is short and known.
const String choiceInstruction =
    'When the next step depends on a decision that is genuinely the user\'s — '
    'a tone, a language, an aspect ratio, which of a few directions to take — '
    'and the sensible answers are a short known set, ask with a fenced '
    '```$choiceFenceTag block containing JSON: '
    '{"question": "...", "options": ["...", "..."], "multiSelect": false}. '
    'Two to $maxChoiceOptions options. Use it instead of asking in prose, not '
    'as well. Do not use it for open questions, for anything you can '
    'reasonably decide yourself, or more than once in a reply.';

final _choiceFence =
    RegExp('```$choiceFenceTag' r'\s*\n([\s\S]*?)```', multiLine: true);

/// Finds a choice block anywhere in a completed reply.
OfferedChoice? findChoiceIn(String text) {
  final match = _choiceFence.firstMatch(text);
  return match == null ? null : parseChoiceBlock(match.group(1)!);
}

/// [text] with the choice block removed.
///
/// Used on the replay path: fenced content that produced no artifact is put
/// back into the reply so nothing is silently dropped, but a block that became
/// a question has already been rendered as one — replaying it too would print
/// the JSON underneath the buttons.
String stripChoiceBlock(String text) =>
    text.replaceAll(_choiceFence, '').trim();
