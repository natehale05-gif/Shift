import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/note.dart';
import '../../data/note_store.dart';
import 'note_screen.dart';

/// Asks before removing a note. No trash, no undo — a mis-tap in a list is
/// the whole note.
Future<bool> confirmDeleteNote(BuildContext context, String title) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this note?'),
      content: Text('"$title" will be removed. This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Notes mode: everything you have said, and a way to say more.
///
/// The list is the mode's whole surface. There is no folder tree and no tag
/// system — a note you dictated is found by reading the first line of it, which
/// is why the row carries the opening words rather than a date and an icon.
class NotesSurface extends StatelessWidget {
  const NotesSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notes = context.watch<NoteStore>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New note'),
      ),
      body: notes.index.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.md, Space.lg, Space.xxl * 2),
              itemCount: notes.index.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 1,
                color: c.divider,
              ),
              itemBuilder: (context, i) => _Row(
                note: notes.index[i],
                onOpen: () => _open(context, notes.index[i].id),
                onDelete: () async {
                  if (!await confirmDeleteNote(context, notes.index[i].title)) {
                    return;
                  }
                  await notes.remove(notes.index[i].id);
                },
              ),
            ),
    );
  }

  void _open(BuildContext context, String? id) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteScreen(
        noteId: id ?? 'note-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ));
  }
}

class _Row extends StatelessWidget {
  final NoteSummary note;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _Row({
    required this.note,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: c.text),
                    ),
                    if (note.preview.isNotEmpty) ...[
                      const SizedBox(height: Space.xxs),
                      Text(
                        note.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: c.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              // Emptying a note also removes it, and that works — but it is
              // not something anybody would guess. A list you can delete from
              // needs a control that says so.
              SizedBox(
                width: kMinTouchTarget,
                height: kMinTouchTarget,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: c.textFaint,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_rounded, size: 32, color: c.textFaint),
            const SizedBox(height: Space.md),
            Text('Nothing written down yet',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.xs),
            Text(
              'Notes you make here can be used as context in the other modes',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: c.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
