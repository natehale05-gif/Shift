import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

/// An executor that records what it was given and answers however the test
/// asks it to.
class _Fake implements StepExecutor {
  final String name;
  final JobOutput Function(JobStep step, Map<String, JobOutput> inputs)? make;
  final String? failWith;
  final bool soft;

  /// What each step actually received, so a test can prove a downstream step
  /// saw an upstream output rather than merely running after it.
  final Map<String, Map<String, JobOutput>> seen = {};
  final List<String> ran = [];

  _Fake(this.name, {this.make, this.failWith, this.soft = false});

  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: name, model: '$name-1');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    ran.add(step.id);
    seen[step.id] = inputs;
    if (failWith != null) {
      yield StepFailed(step.id, reason: failWith!, blocksDependents: !soft);
      return;
    }
    yield StepCompleted(
      step.id,
      make?.call(step, inputs) ?? TextOutput('${step.id} done'),
    );
  }
}

ImageOutput _image(String prompt) => ImageOutput(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
      prompt: prompt,
    );

JobStep _step(
  String id, {
  required Capability needs,
  required OutputKind produces,
  List<String> after = const [],
}) =>
    JobStep(
      id: id,
      needs: needs,
      produces: produces,
      after: after,
      instruction: id,
      label: id,
    );

void main() {
  group('the two-provider graph, which is what this is all for', () {
    test('the image is made by one provider and reaches the other', () async {
      // The headline requirement: generate media with one model and a page
      // with another that uses it. Asserted on what the page step *received*,
      // not merely on ordering — "ran second" and "consumed the picture" are
      // different claims and only one of them is the feature.
      final drawer = _Fake('openai', make: (s, _) => _image('bread'));
      final writer = _Fake('anthropic');

      final graph = JobGraph.build([
        _step('image', needs: Capability.image, produces: OutputKind.image),
        _step('page',
            needs: Capability.text,
            produces: OutputKind.text,
            after: ['image']),
      ]).graph!;

      final events = await JobRunner({
        Capability.image: drawer,
        Capability.text: writer,
      }).run(graph).toList();

      expect(drawer.ran, ['image']);
      expect(writer.ran, ['page']);

      final delivered = writer.seen['page']!;
      expect(delivered.keys, ['image']);
      expect((delivered['image']! as ImageOutput).prompt, 'bread');

      final started = events.whereType<StepStarted>().toList();
      expect(started.map((e) => e.provider), ['openai', 'anthropic'],
          reason: 'each step reports its own provider, not one for the turn');

      expect(events.last, isA<TurnFinished>());
      expect((events.last as TurnFinished).incomplete, isFalse);
    });

    test('independent steps really are in flight at once', () async {
      // Asserting only that all three ran would pass just as well if they ran
      // one after another, which is the thing this is supposed to rule out.
      // So each step blocks until every step has started: run in series, this
      // deadlocks and the test times out. Passing is proof of overlap rather
      // than evidence consistent with it.
      final gate = _Barrier(3);
      final graph = JobGraph.build([
        for (var i = 0; i < 3; i++)
          _step('img$i', needs: Capability.image, produces: OutputKind.image),
      ]).graph!;

      final events = await JobRunner({Capability.image: gate})
          .run(graph)
          .toList()
          .timeout(const Duration(seconds: 5));

      expect(gate.started.toSet(), {'img0', 'img1', 'img2'});
      expect((events.last as TurnFinished).incomplete, isFalse);
    });
  });

  group('partial failure', () {
    test('a soft failure lets the page be written without the picture',
        () async {
      // The behaviour v1 lacked: one flaky provider should not discard work
      // that has already been paid for.
      final drawer = _Fake('openai', failWith: 'timed out', soft: true);
      final writer = _Fake('anthropic');

      final graph = JobGraph.build([
        _step('image', needs: Capability.image, produces: OutputKind.image),
        _step('page',
            needs: Capability.text,
            produces: OutputKind.text,
            after: ['image']),
      ]).graph!;

      final events = await JobRunner({
        Capability.image: drawer,
        Capability.text: writer,
      }).run(graph).toList();

      expect(writer.ran, ['page'], reason: 'the page must still be written');
      expect(writer.seen['page'], isEmpty,
          reason: 'and must be told the picture is missing, not handed a fake');
      expect((events.last as TurnFinished).incomplete, isTrue,
          reason: 'the turn must admit it is partial rather than look whole');
    });

    test('a hard failure skips dependents but not unrelated branches',
        () async {
      final searcher = _Fake('search', failWith: 'no sources');
      final writer = _Fake('anthropic');
      final drawer = _Fake('openai', make: (s, _) => _image('unrelated'));

      final graph = JobGraph.build([
        _step('search', needs: Capability.search, produces: OutputKind.search),
        _step('summary',
            needs: Capability.text,
            produces: OutputKind.text,
            after: ['search']),
        _step('aside', needs: Capability.image, produces: OutputKind.image),
      ]).graph!;

      final events = await JobRunner({
        Capability.search: searcher,
        Capability.text: writer,
        Capability.image: drawer,
      }).run(graph).toList();

      expect(writer.ran, isEmpty, reason: 'the summary had nothing to summarise');
      expect(drawer.ran, ['aside'],
          reason: 'an unrelated branch must not be collateral damage');

      final skipped = events
          .whereType<StepFailed>()
          .where((e) => e.stepId == 'summary')
          .single;
      expect(skipped.reason, contains('search'),
          reason: 'say which step it was waiting on');
      expect((events.last as TurnFinished).incomplete, isTrue);
    });

    test('a missing executor is named as such, not as a provider error',
        () async {
      // The fix is an account or a configuration, not a retry, so it must not
      // read like the provider misbehaved.
      final graph = JobGraph.build([
        _step('clip', needs: Capability.video, produces: OutputKind.video),
      ]).graph!;

      final events = await JobRunner(const {}).run(graph).toList();
      final failed = events.whereType<StepFailed>().single;
      expect(failed.reason, contains('video'));
      expect((events.last as TurnFinished).incomplete, isTrue);
    });

    test('an executor that throws does not hang the turn', () async {
      final graph = JobGraph.build([
        _step('a', needs: Capability.text, produces: OutputKind.text),
      ]).graph!;

      final events = await JobRunner({Capability.text: _Throwing()})
          .run(graph)
          .toList();

      expect(events.whereType<StepFailed>(), hasLength(1));
      expect(events.last, isA<TurnFinished>());
    });

    test('a provider returning the wrong kind is caught', () async {
      // Not redundant with the graph's static validation: the plan says what a
      // step *will* produce, and a provider can return something else. Handing
      // a text output to a step expecting an image fails later and further
      // away.
      final liar = _Fake('openai', make: (s, _) => const TextOutput('oops'));
      final graph = JobGraph.build([
        _step('image', needs: Capability.image, produces: OutputKind.image),
      ]).graph!;

      final events =
          await JobRunner({Capability.image: liar}).run(graph).toList();

      expect(events.whereType<StepFailed>(), hasLength(1));
      expect((events.last as TurnFinished).incomplete, isTrue);
    });
  });

  group('the ordinary case', () {
    test('one step, one answer, complete', () async {
      final graph = JobGraph.build([
        _step('main', needs: Capability.text, produces: OutputKind.text),
      ]).graph!;

      final events = await JobRunner({Capability.text: _Fake('anthropic')})
          .run(graph)
          .toList();

      expect(events.whereType<StepCompleted>(), hasLength(1));
      expect((events.last as TurnFinished).incomplete, isFalse);
    });

    test('the stream always ends', () async {
      // Every path through the runner has to close, or the UI waits forever on
      // a turn that is already over.
      for (final executors in <Map<Capability, StepExecutor>>[
        {Capability.text: _Fake('a')},
        {Capability.text: _Fake('a', failWith: 'no')},
        {Capability.text: _Throwing()},
        const {},
      ]) {
        final graph = JobGraph.build([
          _step('main', needs: Capability.text, produces: OutputKind.text),
        ]).graph!;
        final events = await JobRunner(executors).run(graph).toList();
        expect(events.last, isA<TurnFinished>());
      }
    });
  });
}

class _Throwing implements StepExecutor {
  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'x', model: 'x');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    throw StateError('boom');
  }
}

/// Blocks every step until [count] of them have started.
///
/// A sequential runner can never satisfy this, so it deadlocks rather than
/// quietly passing — which is the point: the test should be able to tell
/// concurrency from a coincidence of ordering.
class _Barrier implements StepExecutor {
  final int count;
  final List<String> started = [];
  final Completer<void> _open = Completer<void>();

  _Barrier(this.count);

  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'openai', model: 'openai-1');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    started.add(step.id);
    if (started.length == count && !_open.isCompleted) _open.complete();
    await _open.future;
    yield StepCompleted(
      step.id,
      ImageOutput(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
        prompt: step.id,
      ),
    );
  }
}
