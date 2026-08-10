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
  AgentRun runFor(String agentId) =>
      _open[agentId] ??= runs.read(agentId);

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

      case AgentUsed(:final result, :final isError, :final changedPath):
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
      await _mark(
        agent,
        ok ? AgentStatus.needsAttention : AgentStatus.failed,
        note: note,
      );
      notifyListeners();
    });
  }

  Future<void> _mark(Agent agent, AgentStatus status, {String? note}) =>
      agents.save(Agent(
        id: agent.id,
        title: agent.title,
        workspaceId: agent.workspaceId,
        status: status,
        diff: agent.diff,
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
