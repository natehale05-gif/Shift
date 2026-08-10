import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_keys_store.dart';
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

  /// Built from the keys on this device. [ApiKeysStore] is passed rather than
  /// read from a context so the controller stays testable with no widgets, and
  /// so "which provider, paid for how" has exactly one answer.
  TurnController({
    ApiKeysStore? keys,
    Map<Capability, StepExecutor> Function()? executors,
  }) : executors = executors ?? (() => _fromKeys(keys));

  bool get running => _running;
  bool get isEmpty => items.isEmpty;

  /// With no key this still resolves to nothing and every step fails with a
  /// sentence naming what is missing — which remains better than a simulated
  /// answer. v1 shipped a demo mode that answered convincingly with no model
  /// behind it, and it made "is this actually working?" unanswerable.
  ///
  /// The membership arm of [resolveAccess] is written and dormant: it needs an
  /// account, which lands with sign-in.
  static Map<Capability, StepExecutor> _fromKeys(ApiKeysStore? keys) {
    bool usable(String id) => keys?.has(id) ?? false;

    Future<ProviderAccess?> access(String id) async {
      final key = keys?.get(id);
      return key == null ? null : DirectKey(key);
    }

    return {
      Capability.text: TextExecutor(usable: usable, access: access),
      Capability.image: ImageExecutor(usable: usable, access: access),
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
