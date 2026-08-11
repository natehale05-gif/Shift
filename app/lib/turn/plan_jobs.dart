import '../shell/mode.dart';
import 'capability.dart';
import 'job_graph.dart';
import 'job_output.dart';
import 'turn_request.dart';

/// Turns a request into a plan. Pure, deterministic, and deliberately modest.
///
/// This is the **floor**, not the ceiling. It recognises a small set of shapes
/// it can be confident about and answers everything else with a single text
/// step. A model planner sits above it for the unusual cases (N1's second
/// half), validated against the same [JobGraph] types and falling back here
/// when it proposes something that will not build.
///
/// Modest on purpose. v1's planner was a keyword table that tried to classify
/// every request, and its failures were the expensive kind: a request for a
/// page answered with a picture, or a multi-part request silently reduced to
/// one part. **A single text step is never wrong in a way that wastes money or
/// discards half of what was asked for** — a language model asked to write a
/// page writes a page. So ambiguity resolves to one step, and the graph is
/// only split when the request plainly names two different kinds of output.
JobGraph planJobs(TurnRequest request) {
  final text = request.input.toLowerCase();

  final wantsPage = _mentions(text, _pageWords);
  final wantsSpoken = _mentions(text, _speechWords);
  final wantsSearch = request.webSearch ||
      request.deepResearch ||
      _mentions(text, _searchWords);

  // The mode supplies a default only when the request names no kind of output
  // at all. "A vase of tulips" typed into Visual is a picture; "write me a
  // caption for this" typed into the same box is not, and a mode that forced
  // the image would be routing rather than defaulting — which is the rule
  // [defaultCapabilityFor] exists to keep.
  //
  // Written first as "names no *other* kind", which is a weaker claim than it
  // reads as: with only page, speech and search words to check against, every
  // question typed into Visual came back as a picture of itself. Hence the
  // prose list — a floor, like the rest of this planner, and the failure it
  // still has is a description mistaken for a question rather than the other
  // way round.
  final silent = !wantsPage && !wantsSpoken && !wantsSearch && !_asksForProse(text);
  final wantsPicture = _mentions(text, _imageWords) ||
      (silent && defaultCapabilityFor(request.mode) == Capability.image);

  final steps = <JobStep>[];

  // Search first when it is wanted, because everything downstream reads
  // better with sources than without them.
  if (wantsSearch) {
    steps.add(JobStep(
      id: 'search',
      needs: Capability.search,
      produces: OutputKind.search,
      instruction: request.prompt,
      label: 'Looking it up',
    ));
  }

  // A picture that something else will use. Only split when the request names
  // *both* a picture and a thing to put it in — "make me a logo" is one step,
  // and treating it as two would produce a page nobody asked for.
  final wantsBoth = wantsPicture && (wantsPage || wantsSpoken);
  if (wantsPicture && wantsBoth) {
    steps.add(JobStep(
      id: 'image',
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: request.prompt,
      label: request.editingImage == null ? 'Drawing' : 'Changing it',
      editing: request.editingImage,
    ));
  }

  if (wantsPicture && !wantsBoth) {
    // A picture, and only a picture.
    steps.add(JobStep(
      id: 'image',
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: request.prompt,
      label: request.editingImage == null ? 'Drawing' : 'Changing it',
      editing: request.editingImage,
    ));
    return JobGraph.build(steps).graph!;
  }

  // The writing step. Present in every graph that is not image-only, because
  // something has to say what was done even when the deliverable is a file.
  steps.add(JobStep(
    id: 'main',
    needs: Capability.text,
    produces: OutputKind.text,
    instruction: request.prompt,
    label: wantsPage ? 'Building' : 'Thinking',
    after: [
      if (wantsSearch) 'search',
      if (wantsPicture && wantsBoth) 'image',
    ],
  ));

  // Reading it aloud is the last step, and it consumes the writing rather than
  // the request — narrating the prompt instead of the answer is a mistake that
  // is obvious once heard and easy to make on paper.
  if (wantsSpoken) {
    steps.add(JobStep(
      id: 'speech',
      needs: Capability.speech,
      produces: OutputKind.audio,
      instruction: request.prompt,
      label: 'Reading it out',
      after: const ['main'],
    ));
  }

  final result = JobGraph.build(steps);

  // The planner constructs its own steps, so a failure here is a bug in this
  // function rather than bad input. Falling back to a single step keeps a
  // mistake from becoming a dead turn — the user gets an answer, and the
  // assertion catches it in development.
  assert(result.graph != null, 'planJobs built an invalid graph: ${result.error}');
  return result.graph ?? _justAnswer(request);
}

JobGraph _justAnswer(TurnRequest request) => JobGraph.build([
      JobStep(
        id: 'main',
        needs: Capability.text,
        produces: OutputKind.text,
        instruction: request.prompt,
        label: 'Thinking',
      ),
    ]).graph!;

/// Whole-word matching.
///
/// Substring matching is why v1 routed "I need a **logo**ut button" to the
/// image studio. The boundaries are what make a keyword table survive contact
/// with ordinary sentences.
bool _mentions(String text, List<String> words) {
  for (final word in words) {
    final pattern = RegExp(r'\b' + RegExp.escape(word) + r'\b');
    if (pattern.hasMatch(text)) return true;
  }
  return false;
}

const _imageWords = [
  'image', 'images', 'picture', 'pictures', 'photo', 'photos',
  'illustration', 'illustrations', 'logo', 'icon', 'artwork', 'drawing',
  'render', 'graphic', 'graphics', 'banner', 'thumbnail', 'headshot',
  'portrait',
];

/// Whether the request plainly asks for words.
///
/// Only consulted to stop a mode default from overriding it, so a miss costs a
/// picture where prose was wanted rather than the reverse — and only inside a
/// mode whose default is not text, which today is Visual and Notes.
bool _asksForProse(String text) =>
    text.trimRight().endsWith('?') ||
    _startsWith(text, _questionOpeners) ||
    _mentions(text, _proseWords);

bool _startsWith(String text, List<String> words) {
  for (final word in words) {
    if (RegExp('^${RegExp.escape(word)}\\b').hasMatch(text.trimLeft())) {
      return true;
    }
  }
  return false;
}

const _questionOpeners = [
  'what', 'why', 'how', 'who', 'when', 'where', 'which', 'is', 'are', 'can',
  'should', 'does', 'do', 'did', 'will', 'would',
];

const _proseWords = [
  'write', 'rewrite', 'explain', 'summarise', 'summarize', 'summary',
  'describe', 'translate', 'caption', 'captions', 'list', 'compare', 'draft',
  'email', 'essay', 'poem', 'story', 'recipe', 'answer', 'tell me',
];

const _pageWords = [
  'page', 'website', 'site', 'landing', 'webpage', 'html', 'app', 'dashboard',
  'form', 'game', 'deck', 'slides', 'presentation', 'poster', 'flyer',
];

const _speechWords = [
  'read it aloud', 'read aloud', 'narrate', 'narration', 'voiceover',
  'voice over', 'say it', 'out loud', 'speak',
];

const _searchWords = [
  'search the web', 'look up', 'latest news', 'current price', 'today',
  'this week', 'right now', 'recent',
];

/// The mode's influence on defaults, kept separate from [planJobs] so the
/// planner stays about the request rather than about where the user was
/// standing.
///
/// **Modes are workspaces, not routers.** A mode may not remove a capability
/// or force one — it only supplies a default when the request is silent. Ask
/// for a landing page in Notes and you get a landing page.
Capability defaultCapabilityFor(AppMode mode) => switch (mode) {
      AppMode.chat => Capability.text,
      AppMode.code => Capability.text,
      AppMode.visual => Capability.image,
      AppMode.design => Capability.text,
      AppMode.work => Capability.text,
      AppMode.notes => Capability.transcription,
    };
