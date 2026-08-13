import '../data/artifact.dart';
import 'job_output.dart';

/// Everything that can happen during a turn.
///
/// Sealed, so a switch over it is exhaustive and adding a case makes the
/// analyzer name every place that has to learn about it. That is the mechanism
/// this codebase leans on hardest: it turns "somebody remembers to handle the
/// new thing" into a compile error.
///
/// The stream is per-*step*, not per-turn. A graph can have several steps in
/// flight at once, so every event carries the step it belongs to and the UI
/// composes rather than assuming a single sequence.
sealed class TurnEvent {
  /// Which step this is about. Empty for turn-level events.
  final String stepId;

  const TurnEvent(this.stepId);
}

/// A step has been picked up, and by whom.
///
/// [provider] is here because the honest answer to "which model made this" has
/// to survive to the UI. In a multi-step turn the answer is different per
/// step — that is the whole point — so a single "model used" label on the turn
/// would be a lie in exactly the case the app is built for.
class StepStarted extends TurnEvent {
  final String label;
  final String provider;
  final String model;

  const StepStarted(
    super.stepId, {
    required this.label,
    required this.provider,
    required this.model,
  });
}

/// Progress on work that takes long enough to need it — a video render, a long
/// document. [fraction] is null when the provider will not say, which is
/// common and must not be shown as 0%.
class StepProgress extends TurnEvent {
  final double? fraction;
  final String? note;

  const StepProgress(super.stepId, {this.fraction, this.note});
}

/// Streamed prose.
class TextDelta extends TurnEvent {
  final String text;

  const TextDelta(super.stepId, this.text);
}

/// Streamed reasoning, shown in a disclosure rather than inline.
class ThinkingDelta extends TurnEvent {
  final String text;

  const ThinkingDelta(super.stepId, this.text);
}

class ToolUseStarted extends TurnEvent {
  final String tool;
  final String? detail;

  const ToolUseStarted(super.stepId, this.tool, {this.detail});
}

class ToolUseFinished extends TurnEvent {
  final String tool;
  final bool ok;

  const ToolUseFinished(super.stepId, this.tool, {this.ok = true});
}

/// Sources, with the spans of text they support.
///
/// Spans rather than a bare list, because the target is Grok-style inline
/// markers in the prose — and a citation that cannot say *which sentence* it
/// backs can only ever be rendered as a chip at the bottom, which is what v1
/// did and what this replaces.
class CitationsFound extends TurnEvent {
  final List<Citation> citations;

  const CitationsFound(super.stepId, this.citations);

  /// The same sources with their offsets dropped.
  ///
  /// For when the displayed text is not the text the offsets were measured
  /// against — which happens whenever a fenced block is withheld from the
  /// transcript and shown as an artifact instead.
  CitationsFound get withoutSpans => CitationsFound(stepId, [
        for (final c in citations) Citation(title: c.title, url: c.url),
      ]);
}

class Citation {
  final String title;
  final Uri url;

  /// Character range in the step's text that this source supports. Null when
  /// the provider gives no offsets, in which case it renders as a plain
  /// source rather than an inline marker — degrading honestly rather than
  /// guessing at a position.
  final int? start;
  final int? end;

  const Citation({
    required this.title,
    required this.url,
    this.start,
    this.end,
  });

  bool get hasSpan => start != null && end != null;
}

/// A step's reply carried a deliverable — a page, a document, a file — that
/// belongs beside the conversation rather than inside it.
///
/// Separate from [StepCompleted] because the two answer different questions:
/// what the next step receives, versus what the person is shown. A page is
/// both, and collapsing them would mean either the panel reading the step's
/// output and guessing, or the next step receiving a widget.
class ArtifactProduced extends TurnEvent {
  final Artifact artifact;

  const ArtifactProduced(super.stepId, this.artifact);
}

/// A step finished and produced something.
class StepCompleted extends TurnEvent {
  final JobOutput output;

  const StepCompleted(super.stepId, this.output);
}

/// A step failed, and the turn carries on where it can.
///
/// **Partial failure is a first-class result.** If the picture fails, the page
/// should still be written and should say the picture is missing — v1
/// collapsed the whole turn instead, so one flaky provider lost work that had
/// already been paid for.
class StepFailed extends TurnEvent {
  /// Shown to a person. Says what failed and what it means for the result.
  final String reason;

  /// Whether steps that depend on this one can still run. False when the
  /// output was essential; true when they can proceed with a hole.
  final bool blocksDependents;

  /// The technical fact behind [reason], for a bug report — an exception name,
  /// a status, the host that was asked. Never shown inline: it is for the
  /// person diagnosing, not the person reading.
  ///
  /// It exists because the alternative is a screenshot of a sentence that four
  /// different faults all produce, which is what made the last regression take
  /// three rounds to place. Never carries a key or a header.
  final String? detail;

  const StepFailed(
    super.stepId, {
    required this.reason,
    this.blocksDependents = true,
    this.detail,
  });
}

/// The turn is over. [incomplete] is set when some steps failed or were
/// skipped, so the UI can say so rather than presenting a partial result as a
/// whole one.
class TurnFinished extends TurnEvent {
  final bool incomplete;
  final String? note;

  const TurnFinished({this.incomplete = false, this.note}) : super('');
}
