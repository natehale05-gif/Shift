import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../providers/access.dart';
import '../../shell/mode.dart';
import '../../turn/capability.dart';
import '../../turn/executors/image_executor.dart';
import '../../turn/executors/text_executor.dart';
import '../../turn/job_runner.dart';
import '../../turn/plan_jobs.dart';
import '../../turn/turn_event.dart';
import '../../turn/turn_request.dart';

/// One thing in the transcript.
sealed class ChatItem {
  const ChatItem();
}

class UserSaid extends ChatItem {
  final String text;

  const UserSaid(this.text);
}

/// A reply, which may still be arriving. One object mutated as deltas land
/// rather than a new list entry per token — the alternative rebuilds the whole
/// transcript on every character.
class Reply extends ChatItem {
  final StringBuffer _text = StringBuffer();
  String? provider;
  String? failure;
  bool done = false;

  String get text => _text.toString();

  void write(String chunk) => _text.write(chunk);
}

/// Runs a turn and exposes it as a transcript.
///
/// Deliberately thin: the deciding is [planJobs] and the doing is [JobRunner],
/// both already tested without any widgets. This exists to hold the list and
/// to translate [TurnEvent]s into something a list can render.
class TurnController extends ChangeNotifier {
  final List<ChatItem> items = [];

  /// How the engine is reached. Injected so a test can drive the surface with
  /// fake executors, and so the real answer to "which provider, paid for how"
  /// stays in one place rather than in a widget.
  final Map<Capability, StepExecutor> Function() executors;

  bool _running = false;
  StreamSubscription<TurnEvent>? _sub;

  TurnController({Map<Capability, StepExecutor> Function()? executors})
      : executors = executors ?? _defaultExecutors;

  bool get running => _running;
  bool get isEmpty => items.isEmpty;

  /// With no key and no plan this resolves to nothing, and every step fails
  /// with a sentence naming what is missing. That is the honest state of the
  /// app today and it is better than a simulated answer: v1 shipped a demo
  /// mode that answered convincingly without a model behind it, and it made
  /// "is this working?" unanswerable.
  static Map<Capability, StepExecutor> _defaultExecutors() {
    Future<ProviderAccess?> noCredential(String _) async => null;
    bool nothingUsable(String _) => false;

    return {
      Capability.text:
          TextExecutor(usable: nothingUsable, access: noCredential),
      Capability.image:
          ImageExecutor(usable: nothingUsable, access: noCredential),
    };
  }

  Future<void> send(String input, {required AppMode mode}) async {
    final text = input.trim();
    if (text.isEmpty || _running) return;

    items.add(UserSaid(text));
    final reply = Reply();
    items.add(reply);
    _running = true;
    notifyListeners();

    final graph = planJobs(TurnRequest(input: text, mode: mode));
    final stream = JobRunner(executors()).run(graph);

    _sub = stream.listen((event) {
      switch (event) {
        case StepStarted(:final provider):
          reply.provider ??= provider;
        case TextDelta(:final text):
          reply.write(text);
        case StepFailed(:final reason):
          reply.failure ??= reason;
        case TurnFinished():
          reply.done = true;
          _running = false;
        default:
          return;
      }
      notifyListeners();
    }, onDone: () {
      reply.done = true;
      _running = false;
      notifyListeners();
    });

    await _sub?.asFuture<void>().catchError((_) {});
  }

  void clear() {
    items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
