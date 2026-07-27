import '../data/models/studio_type.dart';
import '../services/diagram_detection.dart';
import '../services/interactive_artifacts.dart';
import '../services/studio_clarification.dart';
import '../services/studio_composition.dart';
import '../services/studio_response_bank.dart';
import 'turn_input.dart';
import 'turn_plan.dart';

/// Decides what kind of turn this is — the shared "head" of every reply.
///
/// Pure: it reads only [input] and calls pure helpers, performs no I/O, and
/// returns a value. That is the whole point. The mock and live services used to
/// each carry their own copy of this ladder, which is how they drifted apart;
/// now there is one copy, and it can be asserted directly in tests without
/// streams, controllers, fake HTTP clients, or timing.
///
/// Branch order is significant and matches the shipped behaviour: a recipe
/// request is an interactive card even though it also mentions food, a research
/// request outranks a plain web search, and so on.
TurnPlan planTurn(TurnInput input) {
  final conversation = input.conversation;
  final userInput = input.userInput;
  final structuredRequest = input.structuredRequest;
  final options = input.options;

  // A terse follow-up to our own clarifying question ("navy blue") continues
  // the same studio request rather than being reclassified from scratch: the
  // studio comes from that pending question and its answer merges into one
  // complete prompt.
  final pending =
      structuredRequest == null ? findPendingClarification(conversation) : null;

  // A structured request already names its studio, and an answer to a pending
  // question belongs to the studio that asked — neither should be re-planned
  // for composition or re-sniffed for an interactive artifact.
  final fresh = structuredRequest == null && pending == null;

  // One composition decision for the whole turn (see studio_composition):
  // pageAssembly = "build a website with photos" (Code + Image together);
  // editArtifact = "add a hero image to the website" (splice into an existing
  // artifact). Everything else is a single studio.
  final plan = fresh ? planComposition(conversation, userInput) : CompositionPlan.none;

  // Interactive artifacts (recipe cards, quizzes, flashcards, checklists) are
  // self-contained interactive widgets built by Code Studio.
  final interactive = fresh ? InteractiveArtifacts.detect(userInput) : null;

  final wantsBoth = plan.kind == CompositionKind.pageAssembly;

  final studio = interactive != null
      ? StudioType.codeStudio
      : wantsBoth
          ? StudioType.codeStudio
          : isCopyFed(plan.kind)
              ? copyFedHost(plan.kind)
              : isMediaPair(plan.kind)
                  ? mediaPairHost(plan.kind)
                  : (structuredRequest?.studioType ??
                      pending?.$1 ??
                      StudioResponseBank.detectStudio(userInput));

  final effectiveInput =
      pending != null ? '${pending.$2} $userInput'.trim() : userInput;
  final answering = pending != null;

  if (interactive != null) {
    return InteractiveTurn(
      kind: interactive,
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  if (wantsDiagram(userInput)) {
    return DiagramTurn(
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  final wantsResearch =
      options.deepResearch || userInput.toLowerCase().contains('deep research');
  if (wantsResearch) {
    return DeepResearchTurn(
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  if (studio == StudioType.middleware &&
      (options.webSearch || StudioResponseBank.wantsWebSearch(userInput))) {
    return WebSearchTurn(
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  if (isCopyFed(plan.kind)) {
    return CopyFedTurn(
      kind: plan.kind,
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  if (isMediaPair(plan.kind)) {
    return MediaPairTurn(
      kind: plan.kind,
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  // The Avatar studio is a talking head: a portrait plus a voiceover card,
  // which is the same media-pair shape. (A real Heygen video needs a key and
  // is handled by the live backend.)
  if (studio == StudioType.avatarStudio) {
    return MediaPairTurn(
      kind: CompositionKind.talkingAvatar,
      studio: studio,
      effectiveInput: effectiveInput,
      isAnsweringClarification: answering,
    );
  }

  final isEdit = plan.kind == CompositionKind.editArtifact;
  return StudioTurn(
    structuredRequest: structuredRequest,
    composeTarget: isEdit ? plan.editTarget : null,
    composeKind: isEdit ? plan.editKind : null,
    contributors: wantsBoth ? plan.contributors : const <StudioType>{},
    studio: studio,
    effectiveInput: effectiveInput,
    isAnsweringClarification: answering,
  );
}
