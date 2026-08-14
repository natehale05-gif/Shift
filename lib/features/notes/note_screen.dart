import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/note_store.dart';
import 'note_cleaner.dart';

/// One note.
///
/// A plain text field, on purpose. The mode's value is what happens *to* the
/// text — dictated in, tidied by a model — not a formatting toolbar, and every
/// control on this screen that is not about that is a control competing with
/// the words.
class NoteScreen extends StatefulWidget {
  final String noteId;

  const NoteScreen({super.key, required this.noteId});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController _controller;

  /// Captured here rather than looked up when it is needed.
  ///
  /// `context.read` in [dispose] throws: by then this element is out of the
  /// provider's scope, so the lookup fails and the save never happens. The note
  /// was written, the screen closed, and the list came back empty — found by
  /// typing one in, not by any test, because every test held the store itself.
  late final NoteStore _notes;

  /// Saves a moment after typing stops.
  ///
  /// Not per keystroke — that is a write per character — and not only on the
  /// way out, because "only on the way out" is how the chat side lost whole
  /// conversations to a closed tab.
  Timer? _pending;

  static const _quiet = Duration(milliseconds: 700);

  /// The text as it was before the last tidy, so it can be put back.
  ///
  /// A model rewriting your words is the one action here that can lose
  /// something, and the undo has to be in the same place as the button that
  /// did it — not in a menu, and not gone as soon as the screen rebuilds.
  String? _beforeTidy;

  @override
  void initState() {
    super.initState();
    _notes = context.read<NoteStore>();
    _controller = TextEditingController(text: _notes.body(widget.noteId))
      ..addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _pending?.cancel();

    // Deferred past this frame rather than done here. Saving notifies the
    // store, the list is listening, and rebuilding it while this route is
    // being torn down is something the framework refuses outright — so a
    // straight call here throws and the note is lost, which is the same
    // symptom as the `context.read` bug and a different cause.
    final text = _controller.text;
    WidgetsBinding.instance.addPostFrameCallback((_) => _persist(text));

    _controller.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _pending?.cancel();
    _pending = Timer(_quiet, () => _persist(_controller.text));
  }

  void _persist(String text) {
    if (text.trim().isEmpty) {
      // An empty note is not a note. Leaving it would put an "Untitled" row in
      // the list for every time somebody opened the screen and changed nothing.
      if (_notes.body(widget.noteId).isNotEmpty) _notes.remove(widget.noteId);
      return;
    }
    _notes.save(widget.noteId, text);
  }

  Future<void> _tidy() async {
    final cleaner = context.read<NoteCleaner>();
    final before = _controller.text;
    final result = await cleaner.clean(before);
    if (!mounted) return;

    if (result.failure case final failure?) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    if (result.text case final text?) {
      setState(() {
        _beforeTidy = before;
        _controller.text = text;
      });
    }
  }

  void _undoTidy() {
    final before = _beforeTidy;
    if (before == null) return;
    setState(() {
      _controller.text = before;
      _beforeTidy = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cleaner = context.watch<NoteCleaner>();

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_beforeTidy != null)
            TextButton(
              onPressed: _undoTidy,
              child: const Text('Undo tidy'),
            ),
          IconButton(
            onPressed: cleaner.running ? null : _tidy,
            icon: cleaner.running
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.textMuted),
                  )
                : const Icon(Icons.auto_fix_high_rounded),
            tooltip: 'Tidy up',
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: TextField(
          controller: _controller,
          autofocus: _controller.text.isEmpty,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          cursorColor: c.accent,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintText: 'Start typing, or dictate with the keyboard mic',
            hintStyle: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: c.textFaint),
          ),
        ),
      ),
    );
  }
}
