import 'package:flutter/foundation.dart';

import '../../data/account_store.dart';
import '../../data/api_keys_store.dart';
import '../../data/provider_access_source.dart';
import '../../turn/capability.dart';
import '../../turn/executors/text_executor.dart';
import '../../turn/job_graph.dart';
import '../../turn/job_output.dart';
import '../../turn/job_runner.dart';
import '../../turn/turn_event.dart';
import 'clean_transcript.dart';

/// What a cleanup attempt produced.
///
/// A record rather than a thrown exception because failing is ordinary here —
/// no key, no network — and the note must survive it untouched. There is no
/// state in which the original words are gone and the new ones did not arrive.
typedef Cleaned = ({String? text, String? failure, String? detail});

/// Runs a note's text through a model to tidy it.
///
/// Deliberately not [TurnController]: this is one step with no transcript, no
/// artifact and nothing to persist, and borrowing a chat controller for it
/// would mean a note appearing in the sidebar as a conversation.
class NoteCleaner extends ChangeNotifier {
  final ApiKeysStore? keys;

  /// The account, so a membership pays for tidying a note too.
  final AccountStore? account;

  /// Injected so a test drives the real graph with a fake executor.
  final Map<Capability, StepExecutor> Function()? executors;

  bool _running = false;

  NoteCleaner({this.keys, this.account, this.executors});

  bool get running => _running;

  Future<Cleaned> clean(String spoken) async {
    if (_running || spoken.trim().isEmpty) {
      return (text: null, failure: null, detail: null);
    }
    _running = true;
    notifyListeners();

    try {
      // Built through the same validator every other graph goes through, so
      // a one-step job cannot skip the checks a many-step one gets.
      final built = JobGraph.build([
        JobStep(
          id: 'clean',
          needs: Capability.text,
          produces: OutputKind.text,
          instruction: cleanUpRequest(spoken),
          label: 'Tidying up',
        ),
      ]);
      final graph = built.graph;
      if (graph == null) {
        return (
          text: null,
          failure: 'Could not start the tidy.',
          detail: '${built.error}',
        );
      }

      final written = StringBuffer();
      String? failure;
      String? detail;

      await for (final event in JobRunner(_executors()).run(graph)) {
        switch (event) {
          case TextDelta(:final text):
            written.write(text);
          case StepFailed(:final reason, detail: final why):
            failure = reason;
            detail = why;
          default:
            break;
        }
      }

      if (failure != null) {
        return (text: null, failure: failure, detail: detail);
      }

      final tidied = tidyCleanedReply(written.toString());
      // An empty reply is a failure wearing a success's clothes: replacing the
      // note with nothing would delete what the person said.
      if (tidied.isEmpty) {
        return (
          text: null,
          failure: 'Nothing came back, so the note is unchanged.',
          detail: null,
        );
      }
      return (text: tidied, failure: null, detail: null);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Map<Capability, StepExecutor> _executors() {
    if (executors case final build?) return build();
    // The plan first, this device's keys second — the same source Chat and
    // Code use, so tidying a note is covered by a membership exactly as a
    // message is. This asked only about local keys, which is why it was not.
    final source = ProviderAccessSource(keys: keys, account: account);
    return {
      Capability.text: TextExecutor(
        usable: source.usable,
        access: source.access,
        explainUnavailable: source.explain,
        // No conversation: a note is not one, and an artifact extracted from a
        // tidied note would be the note itself in a panel.
        conversationId: () => '',
      ),
    };
  }
}
