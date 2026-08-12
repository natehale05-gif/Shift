import '../../agents/tools.dart';
import '../../agents/work_brief.dart';
import '../../data/agent_store.dart';
import '../code/agent_runner.dart';

/// Work mode's folders and jobs.
///
/// A subclass rather than an [AgentStore] with a different argument because
/// the provider tree keys on the type: two `AgentStore`s in one tree would
/// resolve to whichever was registered last, and the failure would look like
/// Code mode's repositories appearing among somebody's documents.
class WorkAgents extends AgentStore {
  WorkAgents(super.kv) : super(namespace: 'work');
}

/// The same runner, told it is working in a folder of somebody's documents.
///
/// Everything that makes Work different is here and nowhere else: the brief,
/// the two extra tools, and the permission gate. The run, fold, persist and
/// diff logic is the one copy in [AgentRunner] — a second implementation would
/// be two of each and they would drift, which is the failure this whole app was
/// rebuilt to stop repeating.
class WorkRunner extends AgentRunner {
  WorkRunner({
    required WorkAgents super.agents,
    required super.runs,
    super.keys,
    super.account,
    super.openWorkspace,
    super.client,
  }) : super(
          brief: kWorkBrief,
          tools: kWorkTools,
          // The whole reason Work is not Code: no version control, so an
          // overwrite is final and the standing answer has to be the person's.
          gated: true,
        );
}
