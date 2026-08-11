import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/note_store.dart';

/// The notes attached to the next message, and the way to attach one.
///
/// Notes are the only attachment this app has, so this is deliberately about
/// notes rather than a general attachment tray with one kind in it — a generic
/// shell around a single case is a shell that gets the general problem wrong
/// before the second case arrives to define it.
class AttachedNotes extends StatelessWidget {
  final List<String> ids;
  final ValueChanged<List<String>> onChanged;

  const AttachedNotes({super.key, required this.ids, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Checked *before* reaching for the store: with nothing attached there is
    // nothing to look up, and depending on a provider in order to render
    // nothing makes every surface that hosts a composer depend on Notes.
    if (ids.isEmpty) return const SizedBox.shrink();
    final notes = context.watch<NoteStore>();

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: [
          for (final id in ids)
            _Chip(
              label: notes.index
                  .where((n) => n.id == id)
                  .map((n) => n.title)
                  .firstOrNull ??
                  'Note',
              onRemove: () =>
                  onChanged([for (final other in ids) if (other != id) other]),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: c.accentWash,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRemove,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notes_rounded, size: 15, color: c.accent),
              const SizedBox(width: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.text),
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(Icons.close_rounded, size: 15, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks notes to attach.
///
/// Shows only notes with something in them, and says so when there are none
/// rather than opening an empty sheet that looks broken.
class NotePicker extends StatelessWidget {
  final List<String> attached;

  const NotePicker({super.key, required this.attached});

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> attached,
  }) =>
      showModalBottomSheet<List<String>>(
        context: context,
        backgroundColor: context.colors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        builder: (_) => NotePicker(attached: attached),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final notes = context.watch<NoteStore>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Attach a note',
                style: text.titleMedium
                    ?.copyWith(color: c.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.md),
            if (notes.index.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Text(
                  'No notes yet. Anything you write in Notes can be attached '
                  'here.',
                  style: text.bodyMedium?.copyWith(color: c.textMuted),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final note in notes.index)
                      CheckboxListTile(
                        value: attached.contains(note.id),
                        title: Text(note.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: note.preview.isEmpty
                            ? null
                            : Text(note.preview,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (on) => Navigator.of(context).pop([
                          for (final id in attached)
                            if (id != note.id) id,
                          if (on == true) note.id,
                        ]),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
