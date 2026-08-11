import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_keys_store.dart';
import '../../data/artifact.dart';
import '../../data/artifact_store.dart';
import '../../data/conversation_store.dart';
import '../../data/image_store.dart';
import '../../data/made_image.dart';
import '../../data/note_store.dart';
import '../../providers/access.dart';
import '../../shell/mode.dart';
import '../../turn/capability.dart';
import '../../turn/executors/image_executor.dart';
import '../../turn/executors/text_executor.dart';
import '../../turn/job_output.dart';
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

  /// The deliverable this reply produced, if it produced one.
  ///
  /// Stamped on the reply rather than kept in a list beside the transcript, so
  /// the card that reopens it sits where the page was made — and so the
  /// ordering survives a reload without anything having to reconstruct it.
  String? artifactId;

  /// The pictures this reply made, in the order they arrived.
  ///
  /// Ids, not bytes: a transcript is written on every snapshot, and putting a
  /// megabyte of base64 in it would make each of those writes cost more than
  /// the whole conversation. The bytes live in the asset store, which is the
  /// same reason the gallery's index is separate from its images.
  ///
  /// A list rather than one id, because "four variations" is a single reply
  /// with four pictures, and a shape that can only hold one would quietly
  /// keep the last.
  final List<String> imageIds = [];

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
        if (artifactId != null) 'artifactId': artifactId,
        if (imageIds.isNotEmpty) 'imageIds': imageIds,
        // `|| !done` is the load-bearing half. The only way a half-written
        // reply reaches disk is a snapshot taken while it was still arriving,
        // and if that snapshot is what survives — the tab was closed, the app
        // was killed — then it genuinely did not finish. Storing it as
        // complete would present a truncated answer as a whole one, which
        // [fromJson] then cements by forcing `done`.
        //
        // Costs nothing on the terminal write: by then `done` is true and this
        // is exactly `interrupted`.
        'interrupted': interrupted || !done,
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
      ..artifactId = json['artifactId'] as String?
      ..interrupted = json['interrupted'] == true
      ..done = true;
    for (final id in json['imageIds'] is List
        ? json['imageIds'] as List<dynamic>
        : const []) {
      if (id is String && id.isNotEmpty) reply.imageIds.add(id);
    }
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
  ///
  /// `late final` rather than an initializer because the default needs `this`:
  /// the text executor has to be able to ask which conversation is open when it
  /// produces an artifact, and that id does not exist until the first message.
  late final Map<Capability, StepExecutor> Function() executors;

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

  /// Where notes live, so an attached one can be resolved at send time.
  /// Optional, like the other stores, so a test can drive this with no disk.
  final NoteStore? notes;

  /// Notes going with the **next** message.
  ///
  /// Held here rather than in the composer because the composer is built twice
  /// — once on the empty state, once under a conversation — and an attachment
  /// that vanished when the first reply arrived would be a bug nobody could
  /// describe.
  final List<String> attachedNotes = [];

  void attachNotes(List<String> ids) {
    attachedNotes
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// Where pictures are kept. Optional, like the other stores, so a test can
  /// drive the controller with no disk at all.
  final ImageStore? images;

  TurnController({
    ApiKeysStore? keys,
    this.conversations,
    this.artifacts,
    this.notes,
    this.images,
    Map<Capability, StepExecutor> Function()? executors,
    this.snapshotEvery = const Duration(seconds: 3),
  }) {
    this.executors =
        executors ?? () => _fromKeys(keys, () => _conversationId ?? '');
  }

  /// Where deliverables are kept. Optional, like [conversations], so a test can
  /// drive the controller with no disk at all.
  final ArtifactStore? artifacts;

  /// What this conversation produced beside itself, newest last.
  final List<Artifact> produced = [];

  String? _openArtifactId;

  /// The artifact the panel is showing, or null when it is closed.
  Artifact? get openArtifact {
    final id = _openArtifactId;
    if (id == null) return null;
    for (final a in produced.reversed) {
      if (a.id == id) return a;
    }
    return null;
  }

  Artifact? byId(String id) {
    for (final a in produced) {
      if (a.id == id) return a;
    }
    return null;
  }

  void showArtifact(String? id) {
    _openArtifactId = id;
    notifyListeners();
  }

  String? get conversationId => _conversationId;

  /// How often a still-arriving reply is written while it streams.
  ///
  /// Not per delta — that is a serialise-and-write per character. Not never,
  /// either, which is what it was: a tab closed mid-reply lost the whole
  /// exchange, stop button or no stop button. Wall-clock rather than a delta
  /// count, so a fast model and a slow one cost the same number of writes.
  ///
  /// Settable so a test can drive the path without waiting on a real clock.
  final Duration snapshotEvery;

  DateTime? _lastSnapshot;

  /// Guards against overlapping writes. [KvStore.put] is a read-modify-write
  /// of the whole map, so two saves in flight at once can drop each other's
  /// keys — including the index that makes a conversation findable.
  bool _writing = false;

  Future<void> _persist() async {
    // The one line that makes a chat private. Checked here rather than at each
    // of the four call sites, so a new caller cannot forget it.
    if (_private) return;

    final store = conversations;
    final id = _conversationId;
    if (store == null || id == null || items.isEmpty || _writing) return;

    final title = items.whereType<UserSaid>().isEmpty
        ? 'New chat'
        : items.whereType<UserSaid>().first.text;

    _writing = true;
    try {
      await store.save(
        id: id,
        title: title,
        items: [
          for (final item in items)
            if (item is UserSaid) item.toJson() else (item as Reply).toJson(),
        ],
      );
    } finally {
      _writing = false;
      _lastSnapshot = DateTime.now();
    }
  }

  /// Writes mid-turn, at most once per [snapshotEvery].
  ///
  /// The terminal write still happens; this only bounds how much a crash, a
  /// closed tab or a killed app can take with it. Skipped entirely when a
  /// write is already in flight, so a slow disk never queues a backlog of
  /// saves behind a fast stream.
  void _snapshot() {
    final last = _lastSnapshot;
    if (_writing || last == null) return;
    if (DateTime.now().difference(last) < snapshotEvery) return;
    _snapshotting = _persist();
  }

  int _imageSeq = 0;

  /// Names one picture.
  ///
  /// Top-level and pure so the property that matters can actually be asserted.
  /// A timestamp alone very nearly works — a stream's yields land microseconds
  /// apart — which is why a test that only sends a real turn passes with or
  /// without the counter, on this machine, today. But "very nearly" is not the
  /// claim: a step that emits several variations can produce them inside one
  /// microsecond, and two pictures sharing an id is one picture.
  @visibleForTesting
  static String mintImageId(String stepId, DateTime at, int sequence) =>
      'i${at.microsecondsSinceEpoch.toRadixString(36)}-$stepId-$sequence';

  /// Image writes, run one after another rather than at once.
  ///
  /// Each write is bytes to disk *and* an index through [KvStore.put], which
  /// is a read-modify-write of the whole map — so three variations saving
  /// concurrently can drop each other's index entries and leave orphaned
  /// bytes. Serialised, and never awaited by the turn: a picture already on
  /// screen must not wait on a disk.
  Future<void> _imageWrites = Future.value();

  /// Every image write this turn has started, once they have landed.
  ///
  /// Exposed only so a test can await the *write*. Pumping the event queue is
  /// not a substitute — it passes on an idle machine and fails on a loaded
  /// one, which makes it a check that reports the machine rather than the
  /// code.
  @visibleForTesting
  Future<void> get imagesSettled => _imageWrites;

  /// The snapshot in flight, if there is one.
  ///
  /// Exposed only so a test can await the *write* rather than guess at how
  /// many turns of the event loop a real file takes. Pumping the queue is not
  /// a substitute: it passed on this machine and failed on a loaded CI runner,
  /// which makes it a check that reports the machine rather than the code.
  @visibleForTesting
  Future<void> get snapshotting => _snapshotting ?? Future.value();

  Future<void>? _snapshotting;

  /// Opens a stored conversation. Never private: it came off disk, so it is
  /// already kept.
  void open(String id) {
    _private = false;
    _sub?.cancel();
    _sub = null;
    _running = false;
    _conversationId = id;
    items
      ..clear()
      ..addAll(itemsFromJson(conversations?.body(id) ?? const []));
    produced
      ..clear()
      ..addAll(artifacts?.forConversation(id) ?? const []);
    // Deliberately closed: opening a stored conversation is choosing the
    // conversation, not the page inside it. The card in the transcript is how
    // it is reopened.
    _openArtifactId = null;
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
  ///
  /// **And it is saved.** Stopping reaches the stream by *cancelling* the
  /// subscription, and a cancelled subscription fires neither `onDone` nor
  /// `onError` — which is where the only other call to [_persist] lives. So
  /// the one ending a person chooses on purpose was the one ending that never
  /// wrote: stop on the first turn of a chat and the whole conversation was
  /// absent from the sidebar, as though it had not happened.
  ///
  /// Returns a future so a test can await the write. Nothing in the app does —
  /// `Future<void> Function()` is assignable to `VoidCallback`, so the stop
  /// button is wired to it unchanged.
  Future<void> stop() async {
    if (!_running) return;
    _sub?.cancel();
    _sub = null;
    for (final item in items.reversed) {
      if (item is Reply && !item.done) {
        item.done = true;
        item.interrupted = true;
        break;
      }
    }
    _running = false;
    notifyListeners();

    // Before completing the turn, not after. Completing first would let `send`
    // return ahead of the write — the exact fire-and-forget defect recorded
    // below, one method over.
    await _persist();
    if (_turnDone?.isCompleted == false) _turnDone!.complete();
    _turnDone = null;
  }

  /// With no key this still resolves to nothing and every step fails with a
  /// sentence naming what is missing — which remains better than a simulated
  /// answer. v1 shipped a demo mode that answered convincingly with no model
  /// behind it, and it made "is this actually working?" unanswerable.
  ///
  /// The membership arm of [resolveAccess] is written and dormant: it needs an
  /// account, which lands with sign-in.
  static Map<Capability, StepExecutor> _fromKeys(
    ApiKeysStore? keys,
    String Function() conversationId,
  ) {
    bool usable(String id) => keys?.has(id) ?? false;

    Future<ProviderAccess?> access(String id) async {
      final key = keys?.get(id);
      return key == null ? null : DirectKey(key);
    }

    return {
      Capability.text: TextExecutor(
        usable: usable,
        access: access,
        conversationId: conversationId,
      ),
      Capability.image: ImageExecutor(usable: usable, access: access),
    };
  }

  Future<void> send(
    String input, {
    required AppMode mode,
    List<TurnContext> context = const [],
  }) async {
    final text = input.trim();
    if (text.isEmpty || _running) return;

    _last = (input: text, mode: mode);
    _conversationId ??=
        'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    items.add(UserSaid(text));
    final reply = Reply();
    items.add(reply);
    _running = true;
    // The clock starts here, so a turn that finishes inside the window writes
    // once at the end rather than twice. Without it the first delta always
    // snapshots, whatever the interval says.
    _lastSnapshot = DateTime.now();
    notifyListeners();

    // Resolved now rather than when it was attached: a note edited in between
    // goes as it is *now*, because what was attached is the note, not a copy.
    final attached = [
      ...context,
      for (final id in attachedNotes)
        if (notes?.body(id).trim().isNotEmpty ?? false)
          TurnContext(
            title: notes!.index
                    .where((n) => n.id == id)
                    .map((n) => n.title)
                    .firstOrNull ??
                'Note',
            body: notes!.body(id),
          ),
    ];
    attachedNotes.clear();

    final graph =
        planJobs(TurnRequest(input: text, mode: mode, context: attached));
    final stream = JobRunner(executors()).run(graph);

    final done = Completer<void>();
    _turnDone = done;

    _sub = stream.listen((event) {
      switch (event) {
        case StepStarted(:final provider):
          reply.provider ??= provider;
        case TextDelta(:final text):
          reply.write(text);
        case ArtifactProduced(:final artifact):
          // Saved as it arrives rather than with the transcript at the end: an
          // artifact is the thing the turn was *for*, so losing it to a stop
          // or a closed tab is the worst version of the defect N2e fixed.
          produced.add(artifact);
          reply.artifactId = artifact.id;
          // Opened on arrival, which is what every app shaped like this does —
          // the page is the answer, so showing it is not an interruption.
          _openArtifactId = artifact.id;
          // Not in a private chat: a page left in the artifact store would
          // outlive the conversation that made it, which is the promise
          // broken in the least visible way.
          if (!_private) {
            unawaited(artifacts?.save(artifact) ?? Future<void>.value());
          }
        case StepCompleted(output: final ImageOutput image, :final stepId):
          // Kept as it arrives, for the same reason an artifact is: a picture
          // is what the turn was *for*, and losing it to a stop or a closed
          // tab is the worst version of the defect N2e fixed.
          //
          // A private chat keeps nothing, so the picture is shown for the
          // session and never written — the same rule the artifact save
          // follows, and the same reason.
          final id = mintImageId(stepId, DateTime.now(), _imageSeq++);
          reply.imageIds.add(id);
          if (!_private) {
            _imageWrites = _imageWrites.then((_) => images?.save(
                  MadeImage(
                    id: id,
                    prompt: image.prompt,
                    provider: reply.provider ?? '',
                    model: '',
                    mimeType: image.mimeType,
                    createdAt: DateTime.now(),
                    conversationId: _conversationId,
                  ),
                  image.bytes,
                ) ??
                Future<void>.value());
            unawaited(_imageWrites);
          } else {
            // Still needs to be drawable this session. Held in the store's own
            // cache rather than written, so the transcript can find it by id
            // exactly as it would a kept one.
            images?.hold(id, image.bytes);
          }
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
      // Saved when a turn ends, and — at most every few seconds — while it is
      // still arriving. Not on every delta: writing the whole transcript per
      // token would be a serialise-and-write per character. Not only at the
      // end either, which is what it was: a tab closed mid-reply took the
      // whole exchange with it.
      //
      // The terminal write is awaited *before* the turn is declared finished.
      // Fire-and-forget there meant `send` returned before the write landed,
      // so a reload immediately afterwards found nothing — exactly the thing
      // this feature promises not to do.
      _snapshot();
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

  /// Whether this conversation is kept.
  ///
  /// A private chat is never written: no body, no row in the index, nothing to
  /// find afterwards. Leaving it is losing it, which is the whole point, and
  /// the surface says so rather than letting someone discover it.
  ///
  /// **What it does not do**, and the UI says this too: the request still goes
  /// to whichever provider answers it, under whatever terms that provider has.
  /// This is about what *this app* keeps. Claiming more would be the kind of
  /// privacy promise that is worse than none.
  bool get private => _private;
  bool _private = false;

  /// Starts a new conversation. The old one stays on disk — "New chat" means
  /// begin another, not discard the last.
  ///
  /// A private one is discarded on leaving, because it was never anywhere else.
  void clear({bool private = false}) {
    _sub?.cancel();
    _sub = null;
    _running = false;
    _conversationId = null;
    _last = null;
    _private = private;
    items.clear();
    produced.clear();
    _openArtifactId = null;
    attachedNotes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_turnDone?.isCompleted == false) _turnDone!.complete();
    super.dispose();
  }
}
