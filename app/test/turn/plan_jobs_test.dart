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

    test('search feeds the writing', () {
      final graph = planJobs(
          const TurnRequest(input: 'summarise it', webSearch: true));

      expect(graph.steps.map((s) => s.id), ['search', 'main']);
      expect(graph.steps.last.after, contains('search'));
    });

    test('search, picture and page compose into one graph', () {
      final graph = planJobs(const TurnRequest(
        input: 'research the latest news and build a page with an image',
        webSearch: true,
      ));

      expect(graph.steps.map((s) => s.id), ['search', 'image', 'main']);
      expect(graph.capabilities,
          {Capability.search, Capability.image, Capability.text});
      // The page waits for both, which the graph expresses and a list could
      // not.
      expect(graph.steps.last.after, containsAll(['search', 'image']));
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

    test('every mode has a default capability', () {
      for (final mode in AppMode.values) {
        expect(() => defaultCapabilityFor(mode), returnsNormally,
            reason: '$mode');
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
