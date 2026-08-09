import 'dart:async';

import 'capability.dart';
import 'job_graph.dart';
import 'job_output.dart';
import 'turn_event.dart';

/// What actually performs one step.
///
/// One per [Capability], injected. Everything about providers, keys,
/// entitlement and HTTP lives behind this — so the runner's scheduling, which
/// is the part with the interesting bugs, is testable with no network and no
/// fakes beyond a closure.
abstract class StepExecutor {
  /// Names the provider and model, for [StepStarted]. Read before the work
  /// starts so the UI can say who is doing it while it happens rather than
  /// afterwards.
  ({String provider, String model}) identify(JobStep step);

  /// Runs the step. [inputs] holds the outputs of everything in `step.after`,
  /// keyed by step id — missing when a dependency failed softly, which the
  /// executor must handle rather than assume away.
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs);
}

/// Executes a [JobGraph], in dependency order, as concurrently as the graph
/// allows.
///
/// The scheduling rules, all of which are decisions:
///
/// * Everything [JobGraph.ready] returns starts at once. Four gallery images
///   are four steps with no edges, and running them in series would be four
///   times the wait for no reason.
/// * A step that fails **hard** cancels its dependents rather than running
///   them on nothing — but only its dependents. Unrelated branches finish.
/// * A step that fails **soft** lets its dependents run without its output.
///   That is what keeps a page from being lost because a picture timed out;
///   v1 collapsed the whole turn instead, discarding work already paid for.
/// * The turn ends when nothing is running and nothing is ready, and says
///   whether it was complete.
class JobRunner {
  final Map<Capability, StepExecutor> executors;

  const JobRunner(this.executors);

  Stream<TurnEvent> run(JobGraph graph) {
    final controller = StreamController<TurnEvent>();
    _drive(graph, controller);
    return controller.stream;
  }

  Future<void> _drive(
    JobGraph graph,
    StreamController<TurnEvent> controller,
  ) async {
    final outputs = <String, JobOutput>{};
    final finished = <String>{};
    final failedHard = <String>{};
    var incomplete = false;

    // A step is "settled" once it can no longer gate anything — completed,
    // failed, or skipped. `JobGraph.ready` works on settled ids rather than
    // successful ones, or a soft failure would stall its dependents forever.
    final settled = <String>{};

    try {
      while (settled.length < graph.steps.length) {
        final ready = graph
            .ready(settled)
            .where((s) => !settled.contains(s.id))
            .toList();

        if (ready.isEmpty) break;

        // Anything whose dependency failed hard is skipped, not run. Doing
        // this before dispatch keeps a doomed step from being paid for.
        final runnable = <JobStep>[];
        for (final step in ready) {
          final blocked =
              step.after.where(failedHard.contains).toList();
          if (blocked.isEmpty) {
            runnable.add(step);
            continue;
          }
          incomplete = true;
          settled.add(step.id);
          failedHard.add(step.id);
          controller.add(StepFailed(
            step.id,
            reason: 'Skipped because ${blocked.join(', ')} did not finish.',
          ));
        }

        if (runnable.isEmpty) continue;

        final results = await Future.wait([
          for (final step in runnable) _runStep(step, outputs, controller),
        ]);

        for (final result in results) {
          settled.add(result.id);
          if (result.output != null) {
            outputs[result.id] = result.output!;
            finished.add(result.id);
          } else {
            incomplete = true;
            if (result.hard) failedHard.add(result.id);
          }
        }
      }

      // A graph that cannot finish — every remaining step blocked — still ends
      // rather than hanging. `while` above exits on an empty ready set, and
      // this is what makes that visible instead of silent.
      if (settled.length < graph.steps.length) incomplete = true;

      controller.add(TurnFinished(
        incomplete: incomplete,
        note: incomplete ? 'Some steps did not finish.' : null,
      ));
    } catch (error) {
      // A throw here is a bug in the runner rather than a provider failure —
      // those arrive as StepFailed. Ending the stream honestly beats leaving
      // the UI waiting forever on a turn that has already died.
      controller.add(StepFailed('', reason: 'The turn stopped unexpectedly.'));
      controller.add(const TurnFinished(incomplete: true));
    } finally {
      await controller.close();
    }
  }

  Future<({String id, JobOutput? output, bool hard})> _runStep(
    JobStep step,
    Map<String, JobOutput> outputs,
    StreamController<TurnEvent> controller,
  ) async {
    final executor = executors[step.needs];
    if (executor == null) {
      // Nothing can do this. Named plainly rather than reported as a provider
      // error, because the fix is an account or a configuration, not a retry.
      controller.add(StepFailed(
        step.id,
        reason: 'Nothing available can ${step.needs.name} right now.',
      ));
      return (id: step.id, output: null, hard: true);
    }

    final who = executor.identify(step);
    controller.add(StepStarted(
      step.id,
      label: step.label,
      provider: who.provider,
      model: who.model,
    ));

    final inputs = <String, JobOutput>{
      for (final id in step.after)
        if (outputs.containsKey(id)) id: outputs[id]!,
    };

    JobOutput? produced;
    var hard = true;

    try {
      await for (final event in executor.run(step, inputs)) {
        controller.add(event);
        if (event is StepCompleted) produced = event.output;
        if (event is StepFailed) hard = event.blocksDependents;
      }
    } catch (error) {
      controller.add(StepFailed(step.id, reason: _readable(error)));
      return (id: step.id, output: null, hard: true);
    }

    if (produced == null) return (id: step.id, output: null, hard: hard);

    // The executor promised a kind in the plan. Checking is not redundant with
    // the graph's static validation: a provider can return something else, and
    // handing a video to a step expecting an image fails later and further
    // away.
    if (!step.produces.matches(produced)) {
      controller.add(StepFailed(
        step.id,
        reason: 'That step returned something unexpected.',
      ));
      return (id: step.id, output: null, hard: true);
    }

    return (id: step.id, output: produced, hard: false);
  }
}

/// Never the raw exception. A stack trace or a provider's internal message in
/// the transcript tells the reader nothing they can act on, and occasionally
/// tells them something they should not see.
String _readable(Object error) => 'That step could not be completed.';
