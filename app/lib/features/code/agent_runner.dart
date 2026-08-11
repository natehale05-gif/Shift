import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../agents/agent_loop.dart';
import '../../agents/anthropic_agent.dart';
import '../../agents/workspace.dart';
import '../../agents/workspace_local_stub.dart'
    if (dart.library.io) '../../agents/workspace_local_io.dart';
import '../../data/agent.dart';
import '../../data/agent_run.dart';
import '../../data/agent_run_store.dart';
import '../../data/agent_store.dart';
import '../../data/api_keys_store.dart';
import '../../providers/access.dart';
import 'run_changes.dart';

/// Whether a workspace can be worked in here, and what to say when it cannot.
///
/// A record rather than an exception because "no" is an ordinary answer with a
/// sentence attached — a phone genuinely cannot open a folder — and a refusal
/// the person reads is worth more than a stack trace.
typedef OpenedWorkspace = ({AgentWorkspace? workspace, String? refusal});

/// Runs agents, and holds their transcripts.
///
/// One runner for the whole mode rather than one per agent: the reference lists
/// several agents working at once, and a notifier per agent would mean the list
/// screens subscribing to a set that changes as runs start.
class AgentRunner extends ChangeNotifier {
  final AgentStore agents;
  final AgentRunStore runs;
  final ApiKeysStore? keys;

  /// Opens a working copy. Injected so a test drives the real loop against a
  /// real temp directory, and so N9b's server workspace is a new arm here
  /// rather than a change to everything below it.
  final OpenedWorkspace Function(Workspace) openWorkspace;

  /// Injected for the same reason: the transport is the one part of this that
  /// cannot be had in a sandbox.
  final AnthropicAgent Function() client;

  /// What does the work. Claude, because the agent client speaks its tool-use
  /// wire and nothing else does yet.
  final String model;

  final Map<String, AgentRun> _open = {};

  /// What each open run has changed, as of the last read.
  ///
  /// Held here rather than in a `FutureBuilder` on each screen, for two
  /// reasons that turned out to be the same one: the transcript and the diff
  /// screen both need it, and a revert on one has to be visible on the other.
  /// A future per widget gives two answers that drift.
  final Map<String, List<FileChange>> _changes = {};
  final Map<String, StreamSubscription<AgentEvent>> _live = {};

  /// Every write, in order, one at a time.
  ///
  /// [KvStore.put] is a read-modify-write of the whole map, so two saves in
  /// flight at once can drop each other's keys — and with several agents
  /// working there are several streams writing. Chaining onto one future costs
  /// nothing (these are seconds apart) and makes the race unmakeable rather
  /// than unlikely.
  Future<void> _writes = Future.value();

  Future<void> _serialise(Future<void> Function() work) =>
      _writes = _writes.then((_) => work());

  AgentRunner({
    required this.agents,
    required this.runs,
    this.keys,
    OpenedWorkspace Function(Workspace)? openWorkspace,
    AnthropicAgent Function()? client,
    this.model = 'claude-opus-4-8',
  })  : openWorkspace = openWorkspace ?? defaultOpener,
        client = client ?? AnthropicAgent.new;

  /// The only opener that exists today.
  ///
  /// Both refusals are honest rather than hopeful: there is no server workspace
  /// yet, and a browser has no folder to point at. Saying so beats a control
  /// that spins and then fails.
  static OpenedWorkspace defaultOpener(Workspace workspace) =>
      switch (workspace) {
        LocalFolder() when kIsWeb => (
            workspace: null,
            refusal: 'A browser cannot open a folder on your machine. Code '
                'mode works against a local folder in the desktop app.',
          ),
        LocalFolder(:final path) => (
            workspace: LocalWorkspace(path),
            refusal: null,
          ),
        GitHubRepo() => (
            workspace: null,
            refusal: 'Running against a GitHub repository needs the server '
                'workspace, which is not built yet.',
          ),
      };

  /// The transcript for [agentId], read from disk on first ask.
  ///
  /// Baselines come with it here, unlike in the store, because anything holding
  /// a live run may be about to diff it.
  AgentRun runFor(String agentId) => _open[agentId] ??= AgentRun(
        agentId: agentId,
        entries: runs.read(agentId).entries,
        baseline: runs.readBaseline(agentId),
      );

  /// The working copy for [agent]'s workspace, or the reason there is none.
  ///
  /// Exposed so the review can open the same copy the run used without
  /// repeating the local-versus-server arm — one place decides what a
  /// workspace opens to.
  OpenedWorkspace workspaceFor(Agent agent) {
    final workspace = agents.workspace(agent.workspaceId);
    if (workspace == null) {
      return (workspace: null, refusal: 'That workspace has been removed.');
    }
    return openWorkspace(workspace);
  }

  /// What [agentId] has changed, as of the last [refreshChanges].
  ///
  /// Synchronous and possibly empty: a screen paints what is known now and is
  /// rebuilt when the read lands, rather than holding a spinner over a
  /// transcript that is perfectly readable without its diffs.
  List<FileChange> changesOf(String agentId) =>
      List.unmodifiable(_changes[agentId] ?? const []);

  /// Re-reads what [agent] changed. Cheap enough to call after every revert,
  /// which is exactly when the answer moves.
  Future<void> refreshChanges(Agent agent) async {
    final workspace = workspaceFor(agent).workspace;
    if (workspace == null) return;

    final run = runFor(agent.id);
    try {
      _changes[agent.id] = await changesFor(
        workspace: workspace,
        paths: run.changedPaths,
        baseline: run.baseline,
      );
    } catch (_) {
      // A transcript that renders without its diffs is worth more than one
      // that does not render.
      _changes[agent.id] = const [];
    }
    notifyListeners();
  }

  bool isRunning(String agentId) => _live.containsKey(agentId);

  /// Gives [agent] something to do.
  ///
  /// A follow-up **does not replay the previous round's tool calls.** The
  /// workspace is the state, and the system prompt already tells the model it
  /// cannot see a file it has not read — so re-reading is both cheaper than
  /// carrying a transcript of results and more accurate, because the files may
  /// have changed since. What carries over is what was said.
  Future<void> send(Agent agent, String text) async {
    if (isRunning(agent.id)) return;

    final run = runFor(agent.id);
    run.entries.add(RunAsked(text));
    await _mark(agent, AgentStatus.working, note: null);
    notifyListeners();

    final workspace = agents.workspace(agent.workspaceId);
    if (workspace == null) {
      return _end(agent, run, 'That workspace has been removed.');
    }

    final opened = openWorkspace(workspace);
    if (opened.workspace == null) {
      return _end(agent, run, opened.refusal ?? 'That workspace cannot be opened.');
    }

    final key = keys?.get('anthropic');
    if (key == null) {
      return _end(
        agent,
        run,
        'Add an Anthropic key in Settings — the agent needs one to work.',
      );
    }

    final loop = AgentLoop(workspace: opened.workspace!, client: client());
    final events = loop.run(
      instruction: _instructionFrom(run, text),
      access: DirectKey(key),
      model: model,
    );

    final done = Completer<void>();
    _live[agent.id] = events.listen(
      (event) => _fold(agent, run, event),
      onError: (Object error) {
        run.entries.add(RunEnded(
          reason: 'The run stopped unexpectedly.',
          detail: '$error',
        ));
        _finish(agent, run, ok: false, note: 'Unable to complete')
            .whenComplete(() {
          if (!done.isCompleted) done.complete();
        });
      },
      onDone: () async {
        // `AgentDone` has already been folded, but its write may still be in
        // the queue. Waiting on the queue is what makes "the run finished" and
        // "the run is on disk" the same moment for anyone awaiting this.
        await _writes;
        _live.remove(agent.id);
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    notifyListeners();
    return done.future;
  }

  /// Stops a run, and **writes before it says it stopped.**
  ///
  /// A cancelled subscription fires neither `onDone` nor `onError`, so nothing
  /// downstream will write for it. The chat side lost whole conversations to
  /// exactly this and the fix is the same one: persist on the deliberate exit
  /// path, not only on the ones the stream takes by itself.
  Future<void> stop(String agentId) async {
    final live = _live.remove(agentId);
    if (live == null) return;
    await live.cancel();

    final agent = agents.agent(agentId);
    final run = runFor(agentId);
    run.entries.add(const RunEnded(reason: 'Stopped.'));
    if (agent != null) {
      await _finish(agent, run, ok: true, note: 'Stopped');
    } else {
      await _serialise(() => runs.write(run));
    }
    notifyListeners();
  }

  void _fold(Agent agent, AgentRun run, AgentEvent event) {
    switch (event) {
      case AgentSaid(:final text):
        run.entries.add(RunSaid(text));

      case AgentUsing(:final tool, :final input):
        run.entries.add(RunTool(tool: tool, input: input));

      case AgentUsed(
          :final result,
          :final isError,
          :final changedPath,
          :final previousContent
        ):
        // Completed in place rather than appended, so a call appears once. The
        // newest running entry is the one that just finished — tools run
        // sequentially, which is what makes that true.
        for (final entry in run.entries.reversed) {
          if (entry is RunTool && entry.running) {
            entry
              ..result = result
              ..isError = isError
              ..changedPath = changedPath;
            break;
          }
        }
        // First touch wins. The second edit to a file must not overwrite the
        // record of what it looked like before the first.
        if (changedPath != null && previousContent != null) {
          run.baseline.putIfAbsent(changedPath, () => previousContent);
        }

      case AgentDone(:final reason, :final detail):
        run.entries.add(RunEnded(reason: reason, detail: detail));
        _finish(
          agent,
          run,
          ok: reason == null,
          note: reason == null ? null : 'Unable to complete',
        );
        notifyListeners();
        return;
    }

    // Written on every event rather than throttled. An event is a round of the
    // model or a whole tool call — seconds apart, not per token — so the cost
    // is nothing next to what it buys: a run that survives the app being closed
    // while it works.
    _serialise(() => runs.write(run));
    notifyListeners();
  }

  Future<void> _end(Agent agent, AgentRun run, String reason) {
    run.entries.add(RunEnded(reason: reason));
    return _finish(agent, run, ok: false, note: reason);
  }

  Future<void> _finish(
    Agent agent,
    AgentRun run, {
    required bool ok,
    String? note,
  }) {
    _live.remove(agent.id);
    return _serialise(() async {
      await runs.write(run);
      await runs.writeBaseline(run);
      await _mark(
        agent,
        ok ? AgentStatus.needsAttention : AgentStatus.failed,
        note: note,
        diff: await _countLines(agent, run),
      );
      notifyListeners();
    });
  }

  /// What the run actually changed, in lines.
  ///
  /// Measured once, at the end, so every list row carries a real `+N -M`
  /// instead of the `+0 -0` that has been there since the mode was built. Not
  /// recomputed as the review reverts hunks — the row records what the *run*
  /// did, and the diff screen is where what is left is counted.
  Future<DiffStat> _countLines(Agent agent, AgentRun run) async {
    final paths = run.changedPaths;
    if (paths.isEmpty) return const DiffStat();

    final opened = workspaceFor(agent);
    final workspace = opened.workspace;
    if (workspace == null) return const DiffStat();

    try {
      final changes = await changesFor(
        workspace: workspace,
        paths: paths,
        baseline: run.baseline,
      );
      _changes[agent.id] = changes;
      return totalOf(changes);
    } catch (_) {
      // A number nobody can produce is better absent than wrong, and a run that
      // finished must not be reported as failed because counting it did not.
      return const DiffStat();
    }
  }

  Future<void> _mark(
    Agent agent,
    AgentStatus status, {
    String? note,
    DiffStat? diff,
  }) =>
      agents.save(Agent(
        id: agent.id,
        title: agent.title,
        workspaceId: agent.workspaceId,
        status: status,
        diff: diff ?? agent.diff,
        checksPassed: agent.checksPassed,
        note: note,
        updatedAt: DateTime.now(),
      ));

  /// The instruction for this turn, with what was said before it.
  static String _instructionFrom(AgentRun run, String text) {
    final earlier = <String>[];
    for (final entry in run.entries) {
      switch (entry) {
        case RunAsked(:final text):
          earlier.add('Asked: $text');
        case RunSaid(:final text):
          earlier.add('You said: $text');
        case RunTool() || RunEnded():
          break;
      }
    }
    // The last entry is the request being made now; it belongs at the end, not
    // in the recap.
    if (earlier.isNotEmpty) earlier.removeLast();
    if (earlier.isEmpty) return text;

    final recap = earlier.length > 8
        ? earlier.sublist(earlier.length - 8)
        : earlier;
    return 'Earlier in this session:\n${recap.join('\n')}\n\nNow: $text';
  }

  @override
  void dispose() {
    for (final live in _live.values) {
      live.cancel();
    }
    _live.clear();
    super.dispose();
  }
}
