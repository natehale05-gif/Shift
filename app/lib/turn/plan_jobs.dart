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

  final wantsPicture = _mentions(text, _imageWords);
  final wantsPage = _mentions(text, _pageWords);
  final wantsSpoken = _mentions(text, _speechWords);
  final wantsSearch = request.webSearch ||
      request.deepResearch ||
      _mentions(text, _searchWords);

  final steps = <JobStep>[];

  // Search first when it is wanted, because everything downstream reads
  // better with sources than without them.
  if (wantsSearch) {
    steps.add(JobStep(
      id: 'search',
      needs: Capability.search,
      produces: OutputKind.search,
      instruction: request.input,
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
      instruction: request.input,
      label: 'Drawing',
    ));
  }

  if (wantsPicture && !wantsBoth) {
    // A picture, and only a picture.
    steps.add(JobStep(
      id: 'image',
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: request.input,
      label: 'Drawing',
    ));
    return JobGraph.build(steps).graph!;
  }

  // The writing step. Present in every graph that is not image-only, because
  // something has to say what was done even when the deliverable is a file.
  steps.add(JobStep(
    id: 'main',
    needs: Capability.text,
    produces: OutputKind.text,
    instruction: request.input,
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
      instruction: request.input,
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
        instruction: request.input,
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
