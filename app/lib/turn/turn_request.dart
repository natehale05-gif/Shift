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

  const TurnRequest({
    required this.input,
    this.mode = AppMode.chat,
    this.webSearch = false,
    this.deepResearch = false,
    this.pinnedModel,
  });
}
