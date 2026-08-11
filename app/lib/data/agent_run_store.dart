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

  /// Baselines live under their own key, not inside the transcript.
  ///
  /// They are whole files — the largest thing this app stores — and every list
  /// screen decodes transcripts to render its rows. Sharing one value would
  /// mean opening the Inbox parses every file the agent ever touched.
  static const _baselinePrefix = 'code.baseline.';

  final KvStore _kv;

  const AgentRunStore(this._kv);

  Future<void> load() => _kv.load();

  /// The transcript for [agentId], or an empty one when it has never run.
  ///
  /// Baselines are **not** read here. The lists want the entries; only the
  /// review wants the file contents, and it asks for them by name.
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

  /// Each file as it was before this run first touched it.
  Map<String, String> readBaseline(String agentId) {
    final raw = _kv.get('$_baselinePrefix$agentId');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      };
    } catch (_) {
      // Losing a baseline costs the diff, not the file. The agent's work is on
      // disk either way; what goes is the ability to say what it replaced.
      return {};
    }
  }

  Future<void> write(AgentRun run) =>
      _kv.put('$_prefix${run.agentId}', jsonEncode(run.toJson()));

  Future<void> writeBaseline(AgentRun run) => _kv.put(
        '$_baselinePrefix${run.agentId}',
        jsonEncode(run.baseline),
      );

  Future<void> remove(String agentId) async {
    await _kv.remove('$_prefix$agentId');
    await _kv.remove('$_baselinePrefix$agentId');
  }
}
