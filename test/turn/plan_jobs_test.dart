import 'package:flutter_test/flutter_test.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/plan_jobs.dart';
import 'package:shift/turn/turn_request.dart';

List<String> _ids(String input, {AppMode mode = AppMode.chat, bool search = false}) =>
    planJobs(TurnRequest(input: input, mode: mode, webSearch: search))
        .steps
        .map((s) => s.id)
        .toList();

Set<Capability> _caps(String input) =>
    planJobs(TurnRequest(input: input)).capabilities;

void main() {
  group('ambiguity resolves to one step', () {
    test('an ordinary question is one text step', () {
      expect(_ids('what is the capital of France'), ['main']);
      expect(_caps('what is the capital of France'), {Capability.text});
    });

    test('a vague creative request is still one step', () {
      // The deterministic planner is the floor, not the ceiling. Guessing at
      // structure here is how v1 answered a request for a page with a picture.
      expect(_ids('help me with my bakery'), ['main']);
      expect(_ids('make something nice'), ['main']);
    });

    test('a page on its own is one step', () {
      // A language model asked to write a page writes a page. Splitting this
      // would invent an image nobody asked for and bill for it.
      expect(_ids('build me a landing page for a law firm'), ['main']);
      expect(_caps('build me a landing page for a law firm'), {Capability.text});
    });

    test('an image on its own is one image step', () {
      expect(_ids('make me a logo for a coffee shop'), ['image']);
      expect(_caps('make me a logo for a coffee shop'), {Capability.image});
    });
  });

  group('the multi-model case', () {
    test('a page with a picture is two steps, image first', () {
      // The request the whole design exists for: one model makes the media,
      // another builds the page that uses it.
      final graph = planJobs(const TurnRequest(
          input: 'build a landing page for my bakery with a photo of bread'));

      expect(graph.steps.map((s) => s.id), ['image', 'main']);
      expect(graph.capabilities, {Capability.image, Capability.text});
      expect(graph.steps.last.after, contains('image'),
          reason: 'the page must consume the picture, not merely follow it');
    });

    test('write it and read it aloud', () {
      final graph = planJobs(
          const TurnRequest(input: 'write a short poem and read it aloud'));

      expect(graph.steps.map((s) => s.id), ['main', 'speech']);
      expect(graph.steps.last.after, ['main'],
          reason: 'the narration must consume the writing, not the prompt — '
              'narrating the request instead of the answer is obvious once '
              'heard and easy to miss on paper');
    });

    test('looking things up is the writing step, not a step before it', () {
      // This asserted the opposite until N2f, and the opposite is why asking
      // about anything current answered *nothing*: the search step needed a
      // capability no executor could run, a missing executor fails hard, and a
      // hard failure skips every dependent — so the reply was cancelled.
      //
      // Both providers that can search do it as a server-side tool inside the
      // same turn, so there was never a second call to make.
      final graph = planJobs(
          const TurnRequest(input: 'summarise it', webSearch: true));

      expect(graph.steps.map((s) => s.id), ['main']);
      expect(graph.steps.single.search, isTrue);
      expect(graph.steps.single.after, isEmpty);
    });

    test('an ordinary question containing "today" still gets answered', () {
      // The reported shape. "today" is in the trigger list, so this used to
      // produce a two-step graph whose answer step could never run.
      final graph = planJobs(const TurnRequest(input: 'what happened today'));

      expect(graph.steps.map((s) => s.id), ['main']);
      expect(graph.steps.single.search, isTrue,
          reason: 'it should still try to look it up');
      expect(graph.capabilities, isNot(contains(Capability.search)),
          reason: 'but not by needing a provider nothing can supply');
    });

    test('a request that asks for nothing current does not search', () {
      // The other direction: a tool block on every ordinary message is a
      // billable search on every ordinary message.
      expect(planJobs(const TurnRequest(input: 'write me a poem'))
          .steps.single.search, isFalse);
    });

    test('a picture and a page still compose, with search on top', () {
      final graph = planJobs(const TurnRequest(
        input: 'research the latest news and build a page with an image',
        webSearch: true,
      ));

      expect(graph.steps.map((s) => s.id), ['image', 'main']);
      expect(graph.capabilities, {Capability.image, Capability.text});
      // The page waits for the picture, which the graph expresses and a list
      // could not — and it looks things up itself rather than waiting on a
      // step that never had anything to run it.
      expect(graph.steps.last.after, ['image']);
      expect(graph.steps.last.search, isTrue);
    });
  });

  group('word boundaries', () {
    test('a word inside another word does not trigger a step', () {
      // "logout" contains "logo". v1 routed exactly this to the image studio.
      expect(_ids('add a logout button to the page'), ['main'],
          reason: 'logout is not a logo');
      expect(_caps('add a logout button to the page'), {Capability.text});
    });

    test('the same word standing alone does', () {
      expect(_caps('design a logo and a landing page'),
          {Capability.image, Capability.text});
    });
  });

  group('modes supply defaults, never limits', () {
    test('a page asked for in Notes is still a page', () {
      // Modes are workspaces, not routers. This is the promise the whole shell
      // is built on, so it is pinned rather than assumed.
      expect(_ids('build me a landing page', mode: AppMode.notes), ['main']);
      expect(
        planJobs(const TurnRequest(
                input: 'build a page with a photo', mode: AppMode.notes))
            .capabilities,
        {Capability.image, Capability.text},
      );
    });

    test('a bare description in Visual makes a picture', () {
      // The other half of "modes are workspaces": a mode may not remove a
      // capability, but it does supply one when the request names no kind of
      // output at all. Without this, standing in Visual and typing what you
      // want gets you a paragraph about it.
      expect(_ids('a vase of tulips', mode: AppMode.visual), ['image']);
      expect(_ids('a vase of tulips', mode: AppMode.chat), ['main'],
          reason: 'the same words in Chat are still a question');
    });

    test('a request that names its own output beats the mode default', () {
      // Otherwise Visual would be a router, which is exactly what this
      // architecture rejects.
      expect(_ids('write me a caption for this', mode: AppMode.visual),
          ['main']);
      expect(_ids('build me a landing page', mode: AppMode.visual), ['main']);
    });

    test('every mode has a default capability', () {
      for (final mode in AppMode.values) {
        expect(() => defaultCapabilityFor(mode), returnsNormally,
            reason: '$mode');
      }
    });
  });

  group('several pictures', () {
    test('a plural noun still names a picture', () {
      // Whole-word matching, so `logo` does not match "logos" — and the half
      // that was missing was exactly the half people use when they want more
      // than one.
      for (final word in ['logos', 'icons', 'banners', 'portraits',
          'thumbnails', 'renders', 'drawings']) {
        expect(_ids('make me some $word'), ['image'], reason: word);
      }
    });

    test('a count before the pictures makes that many', () {
      expect(_ids('three pictures of a cat'), ['image', 'image-2', 'image-3']);
      expect(_ids('4 logos for a bakery'),
          ['image', 'image-2', 'image-3', 'image-4']);
    });

    test('an adjective between the count and the noun is fine', () {
      expect(_ids('three widescreen pictures of a cat'),
          ['image', 'image-2', 'image-3']);
      expect(_ids('two simple flat icons'), ['image', 'image-2']);
    });

    test('a linking word between them is not', () {
      // "Three cats in pictures" is one picture of three cats. The preposition
      // is the signal that the number belongs to the subject, which is what
      // keeps the loosened pattern from reintroducing the expensive misparse.
      expect(_ids('three cats in pictures'), ['image']);
      expect(_ids('two dogs and three cats as illustrations'), ['image']);
    });

    test('and it errs toward one, on purpose', () {
      // "Three black and white photos" is three, and this makes one — `and`
      // stops the match. Recorded rather than fixed: a false negative costs a
      // second ask, a false positive costs three pictures, and the planner
      // resolves ambiguity to the cheap answer everywhere else too.
      expect(_ids('three black and white photos'), ['image']);
    });

    test('a count before the subject makes one', () {
      // "A picture of three cats" is one picture. Reading it as three would
      // spend three times the money on a misparse, which is the expensive
      // direction of this mistake.
      expect(_ids('a picture of three cats'), ['image']);
      expect(_ids('an illustration of 6 planets'), ['image']);
    });

    test('a vague plural makes one', () {
      // Same rule as the rest of the planner: ambiguity resolves to the cheap
      // answer, and someone who wanted several can say how many.
      expect(_ids('a few variations of a logo'), ['image']);
      expect(_ids('some pictures of a cat'), ['image']);
    });

    test('more than the cap makes the cap', () {
      expect(requestedCopies('ten pictures of a cat'), kMaxCopies);
      expect(requestedCopies('20 images'), kMaxCopies);
    });

    test('the steps have no edges, so they run at once', () {
      // The whole reason for the shape: four pictures in series is four times
      // the wait for no reason.
      final graph = planJobs(const TurnRequest(
          input: 'three pictures of a cat', mode: AppMode.chat));
      for (final step in graph.steps) {
        expect(step.after, isEmpty, reason: step.id);
      }
      expect(graph.ready(const {}), hasLength(3));
    });

    test('variations of a picture all edit the same one', () {
      final graph = planJobs(const TurnRequest(
        input: 'three variations',
        mode: AppMode.visual,
        editingImage: 'img-7',
      ));
      expect(graph.steps, hasLength(3));
      for (final step in graph.steps) {
        expect(step.editing, 'img-7');
      }
    });
  });

  group('every plan is runnable', () {
    test('a wide sample of requests all build valid graphs', () {
      // The planner constructs its own steps, so an invalid graph here would
      // be a bug in the planner rather than bad input — and it would surface
      // as a dead turn rather than as an error.
      const inputs = [
        'hello',
        'make me a logo',
        'build a page with a picture and read it aloud',
        'research today and narrate a summary with an illustration',
        'write a poem',
        'design a poster with artwork',
        '',
        '   ',
      ];
      for (final input in inputs) {
        final graph = planJobs(TurnRequest(input: input));
        expect(graph.steps, isNotEmpty, reason: input);
        // Dependency order: everything a step consumes appears before it.
        final seen = <String>{};
        for (final step in graph.steps) {
          for (final dep in step.after) {
            expect(seen, contains(dep), reason: '$input: ${step.id} -> $dep');
          }
          seen.add(step.id);
        }
      }
    });
  });
}
