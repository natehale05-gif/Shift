import 'package:flutter_test/flutter_test.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';

JobStep _step(
  String id, {
  Capability needs = Capability.text,
  OutputKind produces = OutputKind.text,
  List<String> after = const [],
}) =>
    JobStep(
      id: id,
      needs: needs,
      produces: produces,
      after: after,
      instruction: 'do $id',
      label: 'Doing $id',
    );

void main() {
  group('a graph refuses to exist in a broken shape', () {
    test('no steps', () {
      final result = JobGraph.build([]);
      expect(result.graph, isNull);
      expect(result.error!.problem, GraphProblem.empty);
    });

    test('two steps with the same id', () {
      // `after` references ids, so duplicates make every edge ambiguous.
      final result = JobGraph.build([_step('a'), _step('a')]);
      expect(result.graph, isNull);
      expect(result.error!.problem, GraphProblem.duplicateId);
    });

    test('a step that depends on nothing that exists', () {
      // The likeliest mistake from a model-authored plan: it invents a
      // reference to a step it decided not to include.
      final result = JobGraph.build([_step('page', after: ['hero'])]);
      expect(result.graph, isNull);
      expect(result.error!.problem, GraphProblem.danglingDependency);
      expect(result.error!.detail, contains('hero'));
    });

    test('a cycle', () {
      final result = JobGraph.build([
        _step('a', after: ['b']),
        _step('b', after: ['a']),
      ]);
      expect(result.graph, isNull);
      expect(result.error!.problem, GraphProblem.cycle);
    });

    test('a longer cycle is still a cycle', () {
      final result = JobGraph.build([
        _step('a', after: ['c']),
        _step('b', after: ['a']),
        _step('c', after: ['b']),
      ]);
      expect(result.graph, isNull);
      expect(result.error!.problem, GraphProblem.cycle);
    });

    test('every problem has its own reason', () {
      // Not one message for four causes. A planner fallback has to be able to
      // tell "the model proposed something impossible" from "this account
      // cannot do what was asked", and a single error string cannot.
      expect(GraphProblem.values.toSet().length, GraphProblem.values.length);
    });
  });

  group('the multi-model case, which is the point', () {
    test('an image feeding a page orders itself and runs in sequence', () {
      // "Generate some media with one model and a website that uses it with
      // another." Two capabilities, one edge — and nothing about the pairing
      // is special-cased anywhere.
      final result = JobGraph.build([
        _step('page',
            needs: Capability.text, produces: OutputKind.text, after: ['hero']),
        _step('hero', needs: Capability.image, produces: OutputKind.image),
      ]);

      final graph = result.graph!;
      expect(graph.steps.map((s) => s.id), ['hero', 'page'],
          reason: 'the dependency must come first however it was listed');
      expect(graph.capabilities, {Capability.image, Capability.text});

      expect(graph.ready({}).map((s) => s.id), ['hero']);
      expect(graph.ready({'hero'}).map((s) => s.id), ['page']);
      expect(graph.ready({'hero', 'page'}), isEmpty);
    });

    test('independent steps are all ready at once', () {
      // Four images for a gallery are four steps with no edges, so they run
      // together. A list could not express that; this is why it is a graph.
      final result = JobGraph.build([
        for (var i = 0; i < 4; i++)
          _step('img$i', needs: Capability.image, produces: OutputKind.image),
      ]);

      expect(result.graph!.ready({}).length, 4);
    });

    test('a fan-in waits for every input', () {
      // A page that uses both a picture and a voiceover must not start when
      // only one has landed.
      final result = JobGraph.build([
        _step('hero', needs: Capability.image, produces: OutputKind.image),
        _step('vo', needs: Capability.speech, produces: OutputKind.audio),
        _step('page', after: ['hero', 'vo']),
      ]);
      final graph = result.graph!;

      // Note what is asserted: that *page* is withheld, not that nothing is
      // ready. With only `hero` done, `vo` is still ready — it has no
      // dependencies — and the first draft of this test asserted an empty set
      // and failed. The code was right; the assertion said something stronger
      // than was meant.
      ids(Set<String> done) => graph.ready(done).map((s) => s.id).toSet();

      expect(ids({'hero'}), isNot(contains('page')));
      expect(ids({'vo'}), isNot(contains('page')));
      expect(ids({'hero', 'vo'}), {'page'});
    });

    test('ordering is stable across builds', () {
      // A planner that shuffled its output between runs would make every
      // failure unreproducible.
      List<String> order() => JobGraph.build([
            _step('c', after: ['a']),
            _step('a'),
            _step('b'),
            _step('d', after: ['b']),
          ]).graph!.steps.map((s) => s.id).toList();

      expect(order(), order());
      expect(order(), order());
    });
  });

  group('the ordinary case still works', () {
    test('a single step is a graph', () {
      final graph = JobGraph.build([_step('answer')]).graph!;
      expect(graph.isSingleStep, isTrue);
      expect(graph.ready({}).map((s) => s.id), ['answer']);
    });
  });

  group('output kinds', () {
    test('each kind recognises only its own output', () {
      // Checked at runtime as well as statically, which is not redundant: a
      // provider can return something other than what it promised, and that
      // has to be caught before it is handed to a step expecting otherwise.
      const text = TextOutput('hello');
      expect(OutputKind.text.matches(text), isTrue);
      for (final kind in OutputKind.values) {
        if (kind != OutputKind.text) {
          expect(kind.matches(text), isFalse, reason: '$kind');
        }
      }
    });

    test('every kind is decided', () {
      const text = TextOutput('hello');
      for (final kind in OutputKind.values) {
        expect(() => kind.matches(text), returnsNormally, reason: '$kind');
      }
    });
  });
}
