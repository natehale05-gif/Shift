import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'agent.dart';
import 'kv_store.dart';

/// The workspaces you have added and the agents running in them.
///
/// On the same [KvStore] as everything else, for the same reason and with the
/// same honest caveat: it is the wrong store for this and the right *next* one.
/// The line at which it gets replaced is when agents live on a server and this
/// becomes a cache of something authoritative elsewhere.
class AgentStore extends ChangeNotifier {
  final KvStore _kv;

  /// Which mode's agents these are.
  ///
  /// Code and Work run the same agent over different kinds of folder, so they
  /// share every class here and must not share a list: a repository showing up
  /// among somebody's documents would be a mode leaking into another one.
  /// Defaulted to `code` so the keys Code mode already wrote keep resolving.
  final String namespace;

  List<Workspace>? _workspaces;
  List<Agent>? _agents;

  AgentStore(this._kv, {this.namespace = 'code'});

  String get _workspacesKey => '$namespace.workspaces';
  String get _agentsKey => '$namespace.agents';

  /// **Decoded on first read, not on [load].**
  ///
  /// The sibling stores differ on this and the difference cost a real bug: one
  /// reads through to the [KvStore] every time, so it works whether or not
  /// anybody remembered to warm it up, and this one cached at load — so when
  /// `main` constructed it and did not call [load], Code mode rendered an empty
  /// Inbox over a disk with agents on it. Nothing in the tests could catch that,
  /// because a test always builds its own store and loads it.
  ///
  /// Reading on demand makes the mistake unmakeable rather than documented.
  List<Workspace> get workspaces =>
      List.unmodifiable(_workspaces ??= _decode(_workspacesKey, Workspace.fromJson));

  /// Newest first, which is the order every list in this mode reads in.
  List<Agent> get agents => List.unmodifiable(_agents ??=
      _decode(_agentsKey, Agent.fromJson)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  /// Warms the underlying file. Optional — the getters above do not depend on
  /// it — but worth doing before the first frame so the first read is not a
  /// disk hit while something is being painted.
  Future<void> load() async {
    await _kv.load();
    _workspaces = null;
    _agents = null;
    notifyListeners();
  }

  List<T> _decode<T>(String key, T? Function(Object?) parse) {
    final raw = _kv.get(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return [
        for (final entry in decoded is List ? decoded : const []) ?parse(entry),
      ];
    } catch (_) {
      // A corrupt row costs its list, not the mode.
      return [];
    }
  }

  List<Agent> forWorkspace(String workspaceId) =>
      [for (final a in agents) if (a.workspaceId == workspaceId) a];

  List<Agent> withStatus(AgentStatus status) =>
      [for (final a in agents) if (a.status == status) a];

  /// How many are in each state, for the Inbox's cards.
  int count(AgentStatus status) => withStatus(status).length;

  Workspace? workspace(String id) {
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  Agent? agent(String id) {
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> addWorkspace(Workspace workspace) async {
    _workspaces = [
      for (final w in workspaces)
        if (w.id != workspace.id) w,
      workspace,
    ];
    await _kv.put(
      _workspacesKey,
      jsonEncode([for (final w in workspaces) w.toJson()]),
    );
    notifyListeners();
  }

  Future<void> removeWorkspace(String id) async {
    _workspaces = [for (final w in workspaces) if (w.id != id) w];
    // Its agents go with it. Leaving them would put rows in "All Agents"
    // pointing at a workspace that no longer exists, which reads as the app
    // having lost track rather than as a deliberate removal.
    _agents = [for (final a in agents) if (a.workspaceId != id) a];
    await _kv.put(
      _workspacesKey,
      jsonEncode([for (final w in workspaces) w.toJson()]),
    );
    await _writeAgents();
    notifyListeners();
  }

  Future<void> save(Agent agent) async {
    _agents = [
      for (final a in agents)
        if (a.id != agent.id) a,
      agent,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _writeAgents();
    notifyListeners();
  }

  Future<void> _writeAgents() =>
      _kv.put(_agentsKey, jsonEncode([for (final a in agents) a.toJson()]));
}
