import '../data/models/artifact.dart';
import '../data/models/studio_request.dart';
import '../data/models/studio_type.dart';
import '../features/artifacts/artifact_composition.dart' show ArtifactMediaKind;
import '../features/artifacts/interactive/interactive_content.dart' show InteractiveKind;
import '../services/studio_composition.dart' show CompositionKind;

/// What kind of turn this is, decided before anything is generated.
///
/// This is the *decision* half of a turn: which studio handles it, what shape
/// the answer takes, and what context the answer needs. It is produced by the
/// pure [planTurn] and consumed by a `TurnBackend`, which is the only part that
/// differs between simulated and live responses.
///
/// Splitting the turn this way is what removes the long-standing duplication
/// between the mock and live services: they were making the same decisions
/// twice, in two ladders that had quietly drifted apart.
sealed class TurnPlan {
  /// The studio that owns this turn.
  final StudioType studio;

  /// The prompt to actually answer. When the user is replying to one of our
  /// own clarifying questions this is the original request merged with their
  /// answer, so the studio sees one complete prompt.
  final String effectiveInput;

  /// True when this turn is the user answering a clarifying question we asked,
  /// which suppresses asking another one.
  final bool isAnsweringClarification;

  const TurnPlan({
    required this.studio,
    required this.effectiveInput,
    required this.isAnsweringClarification,
  });
}

/// A self-contained interactive widget — recipe card, quiz, flashcards,
/// checklist — built by Code Studio and rendered inline in the conversation.
class InteractiveTurn extends TurnPlan {
  final InteractiveKind kind;

  const InteractiveTurn({
    required this.kind,
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// A ```mermaid diagram rendered live in the reply.
class DiagramTurn extends TurnPlan {
  const DiagramTurn({
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// Multi-round research with tool activity and citations.
class DeepResearchTurn extends TurnPlan {
  const DeepResearchTurn({
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// A grounded answer backed by web search.
class WebSearchTurn extends TurnPlan {
  const WebSearchTurn({
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// Copy & Scripts writes text, then a media studio produces from it
/// (narrated script, scripted video, jingle).
class CopyFedTurn extends TurnPlan {
  final CompositionKind kind;

  const CopyFedTurn({
    required this.kind,
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// Two media studios producing a paired deliverable (e.g. a talking avatar:
/// portrait plus voiceover).
class MediaPairTurn extends TurnPlan {
  final CompositionKind kind;

  const MediaPairTurn({
    required this.kind,
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}

/// The ordinary path: one studio answers, optionally splicing media into an
/// existing artifact or pulling in contributor studios for a page build.
class StudioTurn extends TurnPlan {
  /// Present when the turn came from a studio form rather than free text.
  final StudioRequest? structuredRequest;

  /// For an "add a hero image to the website" edit: the artifact to splice
  /// into, and which kind of media block to embed. Both null otherwise.
  final Artifact? composeTarget;
  final ArtifactMediaKind? composeKind;

  /// For a page build, the studios feeding the page alongside Code Studio.
  /// Empty for a plain single-studio turn.
  final Set<StudioType> contributors;

  const StudioTurn({
    this.structuredRequest,
    this.composeTarget,
    this.composeKind,
    this.contributors = const {},
    required super.studio,
    required super.effectiveInput,
    required super.isAnsweringClarification,
  });
}
