import '../shell/mode.dart';

/// Everything the planner is allowed to look at.
///
/// A value, not a controller: [planJobs] is pure, so a plan can be asserted in
/// a test with no widgets, no fakes, and no network. That is the property v1's
/// rebuild was organised around and it is worth keeping.
class TurnRequest {
  /// What the person typed or said.
  final String input;

  /// Which mode they were in. Influences *defaults*, never possibilities —
  /// asking for a landing page in Notes still produces a landing page.
  final AppMode mode;

  /// Toggles the composer offers for this turn.
  final bool webSearch;
  final bool deepResearch;

  /// A model the user pinned, if any. Pinning is a statement about the
  /// provider, not about what to make.
  final String? pinnedModel;

  /// Material the person attached — notes, today.
  ///
  /// **Deliberately not part of routing.** A note that happens to mention a
  /// photograph must not turn a question into an image job: what to make is
  /// what they *asked for*, and the attachment is what to make it *from*. So
  /// [planJobs] matches on [input] and sends [prompt].
  final List<TurnContext> context;

  /// A picture this turn is changing rather than making.
  ///
  /// Set by the surface — you pick the picture, then say what to change —
  /// rather than inferred from the words. Inferring it was the other option
  /// and it is the worse one: "make it night" after four pictures is genuinely
  /// ambiguous, and guessing wrong spends money to edit the wrong thing while
  /// looking like it worked.
  ///
  /// **Not part of routing.** An edit is still an image job because the words
  /// or the mode say so; this only says which picture. So [planJobs] matches
  /// on [input] exactly as before and carries this through untouched.
  final String? editingImage;

  const TurnRequest({
    required this.input,
    this.mode = AppMode.chat,
    this.webSearch = false,
    this.deepResearch = false,
    this.pinnedModel,
    this.context = const [],
    this.editingImage,
  });

  /// What the model is given: the attachments, then the request.
  ///
  /// Fenced and labelled so a note reads as material rather than as a second
  /// instruction — the same reason the note tidy fences its input.
  String get prompt {
    if (context.isEmpty) return input;
    final attached = [
      for (final item in context)
        '<attached title="${item.title}">\n${item.body.trim()}\n</attached>',
    ].join('\n\n');
    return 'Use the attached material where it is relevant.\n\n$attached\n\n'
        '$input';
  }
}

/// One thing attached to a turn.
class TurnContext {
  final String title;
  final String body;

  const TurnContext({required this.title, required this.body});
}
