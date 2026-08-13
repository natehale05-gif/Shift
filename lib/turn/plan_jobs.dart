import '../shell/mode.dart';
import 'capability.dart';
import 'design_brief.dart';
import 'history.dart';
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
    // Pictures, and only pictures. Several when the request plainly asked for
    // several — they have no edges between them, so the runner starts them all
    // at once and the wait is one picture's rather than four.
    final copies = requestedCopies(text);
    final shape = requestedAspectRatio(text);
    for (var i = 0; i < copies; i++) {
      steps.add(JobStep(
        id: i == 0 ? 'image' : 'image-${i + 1}',
        needs: Capability.image,
        produces: OutputKind.image,
        instruction: request.prompt,
        label: request.editingImage == null
            ? (copies == 1 ? 'Drawing' : 'Drawing ${i + 1} of $copies')
            : 'Changing it',
        editing: request.editingImage,
        aspectRatio: shape,
      ));
    }
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
    // Design mode's whole reason to exist. Carried on the step rather than
    // folded into the request, so what the model is *asked* stays exactly
    // what the person typed.
    brief: request.mode == AppMode.design ? kDesignBrief : null,
    // The conversation so far, so a follow-up is a follow-up. Without it every
    // message was its own conversation: "make it shorter" arrived with nothing
    // to shorten, and the model answered the only way it could — as though it
    // had been asked for the first time.
    //
    // Only on this step. The image branch above returns before reaching here,
    // which is the intent: a drawing model given the last twenty things that
    // were said would draw something nobody asked for.
    history: trimHistory(request.history),
    // Looking things up is something this step *does*, not something another
    // step does first. Both providers that can search do it as a server-side
    // tool inside the same turn and hand back prose with cited spans — which is
    // the thing worth having, and which a separate step could not produce.
    //
    // It **was** a separate step, and that is why asking about anything current
    // answered nothing at all: no executor could run `Capability.search`, a
    // missing executor fails hard, and a hard failure skips every dependent —
    // so this step was cancelled before it ran, on the strength of the word
    // "today" appearing in an ordinary question.
    search: wantsSearch,
    after: [
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

/// The shape a request asked a picture to be, or null when it did not.
///
/// **"Landscape" and "portrait" alone are deliberately not orientation
/// words.** A landscape is a genre of picture and a portrait is a genre of
/// picture, and "paint me a landscape" asking for a 16:9 crop of a person's
/// face would be the same class of mistake as reading "a picture of three
/// cats" as three pictures. The orientation reading needs the word to be
/// doing orientation work — "landscape orientation", "portrait format" — or a
/// word that only ever means shape.
///
/// An explicit ratio the provider does not accept reads as null rather than
/// being passed through, because a rejected request is a failed turn where a
/// model-chosen shape would have been a picture.
String? requestedAspectRatio(String text) {
  final lower = text.toLowerCase();

  final explicit = RegExp(r'\b(\d{1,2}\s*:\s*\d{1,2})\b').firstMatch(lower);
  if (explicit != null) {
    final ratio = explicit.group(1)!.replaceAll(RegExp(r'\s+'), '');
    return kAspectRatios.contains(ratio) ? ratio : null;
  }

  for (final entry in _shapeWords.entries) {
    if (_mentions(lower, [entry.key])) return entry.value;
  }
  return null;
}

/// What the provider accepts. Anything else is not sent.
const kAspectRatios = {
  '1:1', '2:3', '3:2', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9', '21:9',
};

/// Ordered: the longer phrases are checked before the bare words they contain,
/// so "portrait orientation" is not read as "portrait".
const _shapeWords = {
  'landscape orientation': '16:9',
  'landscape format': '16:9',
  'portrait orientation': '9:16',
  'portrait format': '9:16',
  'phone wallpaper': '9:16',
  'desktop wallpaper': '16:9',
  'square': '1:1',
  'widescreen': '16:9',
  'cinematic': '21:9',
  'ultrawide': '21:9',
  'banner': '16:9',
  'vertical': '9:16',
  'tall': '9:16',
  'wide': '16:9',
};

/// The most this will make from one request.
///
/// Four rather than none and four rather than ten: every extra step is another
/// picture paid for, so this is the number where "a set to choose from" stops
/// and "a bill you did not expect" starts. A request for more makes four —
/// silently, which is the one dishonest edge here and is preferred to either
/// spending ten pictures' worth or ignoring a plain instruction entirely.
const kMaxCopies = 4;

/// How many pictures a request asked for.
///
/// **The number has to modify the pictures, not the subject.** "Three pictures
/// of a cat" is three; "a picture of three cats" is one, and reading the
/// second as three would spend three times the money on a misparse. So the
/// pattern requires a count immediately before a plural word that names the
/// output.
///
/// A vague plural — "a few", "some variations" — makes one. That is the same
/// rule the rest of this planner follows: ambiguity resolves to the cheap
/// answer, and someone who wanted several can say how many.
int requestedCopies(String text) {
  final match = _countPattern.firstMatch(text.toLowerCase());
  if (match == null) return 1;
  final word = match.group(1)!;
  final n = int.tryParse(word) ?? _numberWords[word] ?? 1;
  return n < 1 ? 1 : (n > kMaxCopies ? kMaxCopies : n);
}

const _numberWords = {
  'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
  'eight': 8, 'nine': 9, 'ten': 10,
};

/// A count, then the thing being counted.
///
/// Up to two words may sit between them, so "three widescreen pictures" and
/// "four detailed logos" count — an adjective is the normal case, and a
/// pattern that only matched the bare noun quietly made one picture out of
/// most real requests.
///
/// **But no linking word may sit between them** — a preposition or a
/// conjunction, never an adjective. Those are the words that change what is
/// being counted: "three cats in pictures" is one picture of three cats, and
/// the preposition is the whole signal that the number belongs to the subject.
/// A category rather than a list of the examples that happened to fail, which
/// is how a keyword table turns into a pile of patches.
///
/// It errs one way on purpose. "Three black and white photos" makes one,
/// because `and` stops the match — a false negative that costs a second ask,
/// against a false positive that costs three pictures. That is the same trade
/// the rest of this planner makes.
final _countPattern = RegExp(
  r'\b(\d{1,2}|two|three|four|five|six|seven|eight|nine|ten)\s+'
  r'(?:(?!(?:of|in|on|at|to|as|for|from|with|and|or|by)\b)\w+\s+){0,2}'
  r'(?:pictures|images|photos|illustrations|logos|icons|renders|graphics|'
  r'banners|thumbnails|portraits|variations|versions|options|takes)\b',
);

/// Words that name a picture.
///
/// **Both numbers of every noun.** Matching is whole-word, so `logo` does not
/// match "logos" — which meant "make me some logos" was answered with prose
/// while "make me a logo" drew one. The half that was missing was exactly the
/// half people use when they want more than one.
const _imageWords = [
  'image', 'images', 'picture', 'pictures', 'photo', 'photos',
  'illustration', 'illustrations', 'logo', 'logos', 'icon', 'icons',
  'artwork', 'drawing', 'drawings', 'render', 'renders',
  'graphic', 'graphics', 'banner', 'banners', 'thumbnail', 'thumbnails',
  'headshot', 'headshots', 'portrait', 'portraits',
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
