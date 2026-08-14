import 'capability.dart';
import 'history.dart';
import 'job_output.dart';

/// One unit of work.
///
/// A step names a [Capability] rather than a provider, and names the steps it
/// consumes by id. That is the whole trick: "make a picture, then build a page
/// that uses it" is two steps and one edge, and which model does which is
/// resolved separately from what the work is.
class JobStep {
  /// Unique within a graph, and referenced by [after].
  final String id;

  /// What kind of provider can run this.
  final Capability needs;

  /// What this step will produce, declared up front so the graph can be
  /// checked before anything is spent.
  final OutputKind produces;

  /// Ids whose outputs this step consumes. Order is not significant; the
  /// runner passes them by id.
  final List<String> after;

  /// What this step is being asked to do. Interpreted by the executor for the
  /// capability — a prompt for [Capability.text], a description for
  /// [Capability.image], a query for [Capability.search].
  final String instruction;

  /// A short label for the UI while this runs. Written for a person watching:
  /// "Drawing the hero image", not "image_step_2".
  final String label;

  /// A stored thing this step is *changing* rather than making.
  ///
  /// Deliberately an id and not bytes: a plan is a value that gets compared,
  /// logged and held, and putting a megabyte of picture inside one would make
  /// every one of those expensive. The executor resolves it.
  ///
  /// Distinct from [after], which names a step in *this* graph. An edit source
  /// was made by an earlier turn, possibly weeks ago, so the graph has nothing
  /// to point at.
  final String? editing;

  /// The shape a picture should be, as a provider-neutral `w:h` string.
  ///
  /// Null means nobody asked, and that travels as *nothing* rather than as a
  /// default: the model picks a shape suited to the subject, and forcing a
  /// square every time would be the app deciding something it was not asked
  /// to decide.
  final String? aspectRatio;

  /// Standing instructions for how this step's output should be made, as
  /// opposed to what it should say.
  ///
  /// Decided by the planner from the mode, and merged into the system prompt
  /// by the executor rather than into [instruction]: it is not part of the
  /// request, and putting it there would make it something the model could
  /// answer *about* instead of follow.
  final String? brief;

  /// The conversation this step is a continuation of, oldest first.
  ///
  /// Empty on every step that does not talk to a language model. An image step
  /// does not get the transcript: the picture is made from [instruction], and
  /// handing a drawing model the last twenty things that were said would
  /// change what it draws for no reason anyone asked for.
  final List<Exchange> history;

  /// Whether this step should look things up as it answers.
  ///
  /// **A property of the writing step, not a step of its own.** Both providers
  /// that can search do it as a server-side tool *inside* the same turn, so a
  /// separate search step would need a standalone search provider nobody has a
  /// key for — and its output would be a bare list of links, which is the
  /// citation-chips-at-the-bottom shape that [Citation]'s offsets exist to
  /// replace.
  ///
  /// It was a separate step, and that is why asking about anything current
  /// produced **no answer at all**: nothing could run `Capability.search`, a
  /// missing executor fails hard, and a hard failure skips every dependent —
  /// so the writing step was cancelled before it started.
  final bool search;

  const JobStep({
    required this.id,
    required this.needs,
    required this.produces,
    required this.instruction,
    this.search = false,
    required this.label,
    this.after = const [],
    this.editing,
    this.aspectRatio,
    this.brief,
    this.history = const [],
  });

  @override
  String toString() => 'JobStep($id: $needs -> $produces, after: $after)';
}

/// Why a graph was refused.
///
/// Distinct reasons rather than one message, because they have different
/// causes and different fixes — and because a model-authored graph will hit
/// these, and "the planner proposed something impossible" needs to be
/// distinguishable from "you asked for something we cannot do".
enum GraphProblem {
  /// Two steps share an id, so `after` references are ambiguous.
  duplicateId,

  /// A step depends on an id no step produces.
  danglingDependency,

  /// The dependencies form a cycle, so nothing can start.
  cycle,

  /// No steps at all.
  empty,
}

class GraphError {
  final GraphProblem problem;
  final String detail;

  const GraphError(this.problem, this.detail);

  @override
  String toString() => '$problem: $detail';
}

/// A validated plan for one turn.
///
/// The constructor is private and [build] is the only way in, so an invalid
/// graph cannot exist. That matters more than usual here: one source of graphs
/// is a model, and a planner whose output is not validated will eventually
/// propose a cycle, a dangling edge, or a step that consumes something nothing
/// makes — each of which fails deep inside execution, after money is spent, in
/// a way that reads as the app being broken.
class JobGraph {
  final List<JobStep> steps;

  const JobGraph._(this.steps);

  /// Validates and builds, or returns what is wrong.
  ///
  /// Returns a record rather than throwing: the caller that matters most is a
  /// fallback path deciding whether to use a model's proposal or its own
  /// deterministic one, and that is control flow, not an exception.
  static ({JobGraph? graph, GraphError? error}) build(List<JobStep> steps) {
    if (steps.isEmpty) {
      return (
        graph: null,
        error: const GraphError(GraphProblem.empty, 'no steps'),
      );
    }

    final byId = <String, JobStep>{};
    for (final step in steps) {
      if (byId.containsKey(step.id)) {
        return (
          graph: null,
          error: GraphError(GraphProblem.duplicateId, step.id),
        );
      }
      byId[step.id] = step;
    }

    for (final step in steps) {
      for (final dependency in step.after) {
        if (!byId.containsKey(dependency)) {
          return (
            graph: null,
            error: GraphError(
              GraphProblem.danglingDependency,
              '${step.id} needs $dependency, which no step produces',
            ),
          );
        }
      }
    }

    final order = _topologicalOrder(steps, byId);
    if (order == null) {
      return (
        graph: null,
        error: const GraphError(
          GraphProblem.cycle,
          'the steps depend on each other in a loop',
        ),
      );
    }

    // Stored in dependency order, so a runner can walk the list and know
    // everything a step consumes is already done.
    return (graph: JobGraph._(order), error: null);
  }

  /// The steps that can start now, given what has already finished.
  ///
  /// This is what makes a graph better than a list: four images for a gallery
  /// are four steps with no edges between them, so they run at once rather
  /// than one after another.
  List<JobStep> ready(Set<String> completed) => [
        for (final step in steps)
          if (!completed.contains(step.id) &&
              step.after.every(completed.contains))
            step,
      ];

  /// Every capability this graph will need, which is what routing checks
  /// against an account's entitlement *before* the turn starts rather than
  /// halfway through.
  Set<Capability> get capabilities => {for (final s in steps) s.needs};

  bool get isSingleStep => steps.length == 1;

  @override
  String toString() => 'JobGraph(${steps.map((s) => s.id).join(' -> ')})';
}

/// Kahn's algorithm. Null when a cycle makes a complete ordering impossible.
///
/// Ties are broken by the caller's original order, so the same input always
/// produces the same plan — a planner that shuffled its output between runs
/// would make every failure unreproducible.
List<JobStep>? _topologicalOrder(
  List<JobStep> steps,
  Map<String, JobStep> byId,
) {
  final remaining = <String, int>{
    for (final step in steps) step.id: step.after.length,
  };
  final dependents = <String, List<String>>{};
  for (final step in steps) {
    for (final dependency in step.after) {
      dependents.putIfAbsent(dependency, () => []).add(step.id);
    }
  }

  final ordered = <JobStep>[];
  final queue = [
    for (final step in steps)
      if (remaining[step.id] == 0) step.id,
  ];

  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    ordered.add(byId[id]!);
    for (final next in dependents[id] ?? const <String>[]) {
      final left = remaining[next]! - 1;
      remaining[next] = left;
      if (left == 0) queue.add(next);
    }
  }

  return ordered.length == steps.length ? ordered : null;
}
