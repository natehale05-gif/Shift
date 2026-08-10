import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_keys_store.dart';
import '../../data/conversation_store.dart';
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

  Map<String, dynamic> toJson() => {'role': 'user', 'text': text};
}

/// A reply, which may still be arriving. One object mutated as deltas land
/// rather than a new list entry per token — the alternative rebuilds the whole
/// transcript on every character.
class Reply extends ChatItem {
  final StringBuffer _text = StringBuffer();
  String? provider;
  String? failure;

  /// The technical fact behind [failure]. Shown only behind a disclosure, and
  /// stored, because the failure worth diagnosing is usually the one that
  /// already scrolled off screen.
  String? failureDetail;

  bool done = false;

  /// Stopped by the user rather than by the model finishing. Kept separate
  /// from [failure] because it is not one: nothing went wrong, and labelling
  /// a deliberate stop as an error is how an app makes someone doubt an
  /// action they took on purpose.
  bool interrupted = false;

  String get text => _text.toString();

  void write(String chunk) => _text.write(chunk);

  Map<String, dynamic> toJson() => {
        'role': 'reply',
        'text': text,
        if (provider != null) 'provider': provider,
        if (failure != null) 'failure': failure,
        if (failureDetail != null) 'failureDetail': failureDetail,
        'interrupted': interrupted,
      };

  /// A stored reply is always finished. A half-written one is not worth
  /// restoring, and writing `done: false` to disk would let a "still
  /// arriving" state survive a restart with nothing arriving.
  static Reply fromJson(Map<String, dynamic> json) {
    final reply = Reply()
      ..write('${json['text'] ?? ''}')
      ..provider = json['provider'] as String?
      ..failure = json['failure'] as String?
      ..failureDetail = json['failureDetail'] as String?
      ..interrupted = json['interrupted'] == true
      ..done = true;
    return reply;
  }
}

/// Rebuilds a transcript from what was stored, skipping anything unreadable
/// rather than failing the whole conversation.
List<ChatItem> itemsFromJson(List<dynamic> raw) => [
      for (final entry in raw)
        if (entry is Map<String, dynamic>)
          if (entry['role'] == 'user')
            UserSaid('${entry['text'] ?? ''}')
          else
            Reply.fromJson(entry),
    ];

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

  /// Completed when the turn ends *for any reason*, including being stopped.
  ///
  /// [send] used to await `_sub.asFuture()`, which never completes once the
  /// subscription is cancelled — so stopping a turn left that future hanging
  /// forever. Invisible in the app, because nothing awaits `send`, and caught
  /// by a test that did.
  Completer<void>? _turnDone;

  /// Built from the keys on this device. [ApiKeysStore] is passed rather than
  /// read from a context so the controller stays testable with no widgets, and
  /// so "which provider, paid for how" has exactly one answer.
  /// Where conversations are kept. Optional so a test can drive the
  /// controller with no disk at all.
  final ConversationStore? conversations;

  /// The conversation being added to. Minted on the first message rather than
  /// at construction, so opening the app does not create an empty row in the
  /// sidebar that nobody asked for.
  String? _conversationId;

  TurnController({
    ApiKeysStore? keys,
    this.conversations,
    Map<Capability, StepExecutor> Function()? executors,
  }) : executors = executors ?? (() => _fromKeys(keys));

  String? get conversationId => _conversationId;

  Future<void> _persist() async {
    final store = conversations;
    final id = _conversationId;
    if (store == null || id == null || items.isEmpty) return;

    final title = items.whereType<UserSaid>().isEmpty
        ? 'New chat'
        : items.whereType<UserSaid>().first.text;

    await store.save(
      id: id,
      title: title,
      items: [
        for (final item in items)
          if (item is UserSaid) item.toJson() else (item as Reply).toJson(),
      ],
    );
  }

  /// Opens a stored conversation.
  void open(String id) {
    _sub?.cancel();
    _sub = null;
    _running = false;
    _conversationId = id;
    items
      ..clear()
      ..addAll(itemsFromJson(conversations?.body(id) ?? const []));
    _last = null;
    notifyListeners();
  }

  bool get running => _running;
  bool get isEmpty => items.isEmpty;

  /// The last thing asked, so it can be asked again. Retry re-runs the
  /// request; it does not replay the answer.
  ({String input, AppMode mode})? _last;

  bool get canRetry => _last != null && !_running;

  Future<void> retry() async {
    final last = _last;
    if (last == null || _running) return;

    // The previous exchange goes, rather than a second copy of the question
    // appearing below the first. Asking again replaces the answer.
    if (items.isNotEmpty && items.last is Reply) items.removeLast();
    if (items.isNotEmpty && items.last is UserSaid) items.removeLast();

    await send(last.input, mode: last.mode);
  }

  /// Stops the turn where it is. What arrived is kept — half an answer is
  /// worth more than none, and discarding it would punish someone for
  /// changing their mind.
  void stop() {
    if (!_running) return;
    _sub?.cancel();
    _sub = null;
    _turnDone?.complete();
    _turnDone = null;
    for (final item in items.reversed) {
      if (item is Reply && !item.done) {
        item.done = true;
        item.interrupted = true;
        break;
      }
    }
    _running = false;
    notifyListeners();
  }

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

    _last = (input: text, mode: mode);
    _conversationId ??=
        'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    items.add(UserSaid(text));
    final reply = Reply();
    items.add(reply);
    _running = true;
    notifyListeners();

    final graph = planJobs(TurnRequest(input: text, mode: mode));
    final stream = JobRunner(executors()).run(graph);

    final done = Completer<void>();
    _turnDone = done;

    _sub = stream.listen((event) {
      switch (event) {
        case StepStarted(:final provider):
          reply.provider ??= provider;
        case TextDelta(:final text):
          reply.write(text);
        case StepFailed(:final reason, :final detail):
          reply.failure ??= reason;
          reply.failureDetail ??= detail;
        case TurnFinished():
          reply.done = true;
          _running = false;
        default:
          return;
      }
      notifyListeners();
      // Saved when a turn ends, not on every delta: writing the whole
      // transcript per token would be a serialise-and-write per character.
      //
      // Awaited *before* the turn is declared finished. Fire-and-forget here
      // meant `send` returned before the write landed, so a reload
      // immediately afterwards found nothing — which is exactly the thing
      // this feature promises not to do.
    }, onDone: () async {
      reply.done = true;
      _running = false;
      notifyListeners();
      await _persist();
      if (!done.isCompleted) done.complete();
    }, onError: (_) async {
      reply.done = true;
      _running = false;
      notifyListeners();
      await _persist();
      if (!done.isCompleted) done.complete();
    });

    await done.future;
  }

  /// Starts a new conversation. The old one stays on disk — "New chat" means
  /// begin another, not discard the last.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _running = false;
    _conversationId = null;
    _last = null;
    items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_turnDone?.isCompleted == false) _turnDone!.complete();
    super.dispose();
  }
}
