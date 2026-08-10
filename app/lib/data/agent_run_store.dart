import 'dart:convert';

import 'agent_run.dart';
import 'kv_store.dart';

/// Transcripts, kept between launches.
///
/// One key per agent rather than one list of everything: a transcript is only
/// ever read when its agent is open, and a run that ran to the round limit is
/// the largest thing this app stores. Loading forty of them to show one would
/// be the whole mode's worth of text for a single screen.
///
/// Same honest caveat as its sibling stores: [KvStore] is the wrong store for
/// this and the right *next* one. The line at which it gets replaced is when
/// runs live on a server and this becomes a cache of something authoritative
/// elsewhere.
class AgentRunStore {
  static const _prefix = 'code.run.';

  final KvStore _kv;

  const AgentRunStore(this._kv);

  Future<void> load() => _kv.load();

  /// The transcript for [agentId], or an empty one when it has never run.
  AgentRun read(String agentId) {
    final raw = _kv.get('$_prefix$agentId');
    if (raw == null) return AgentRun(agentId: agentId);
    try {
      return AgentRun.fromJson(agentId, jsonDecode(raw));
    } catch (_) {
      // A corrupt row costs that transcript, not the mode. The agent is still
      // in the list, and starting it again writes a fresh one.
      return AgentRun(agentId: agentId);
    }
  }

  Future<void> write(AgentRun run) =>
      _kv.put('$_prefix${run.agentId}', jsonEncode(run.toJson()));

  Future<void> remove(String agentId) => _kv.remove('$_prefix$agentId');
}
