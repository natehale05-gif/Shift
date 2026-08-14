import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Create/edit dialog for a custom response style. Returns (name, instructions)
/// or null if cancelled. Shared by the composer style picker and Settings.
Future<(String, String)?> showStyleEditorDialog(
  BuildContext context, {
  String initialName = '',
  String initialInstructions = '',
}) {
  final nameController = TextEditingController(text: initialName);
  final instructionsController =
      TextEditingController(text: initialInstructions);
  final isEdit = initialName.isNotEmpty;
  return showDialog<(String, String)>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isEdit ? 'Edit style' : 'Create style'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Executive summary, Playful, Socratic',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: instructionsController,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                hintText: 'How should SHIFT AI write in this style? '
                    '(tone, length, formatting, perspective…)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        // Enabled only once both fields have something in them. It used to be
        // always enabled and return early when they did not, which reads as a
        // broken button: you press Create, nothing happens, and nothing says
        // why. A disabled button answers the question before it is asked.
        ListenableBuilder(
          listenable: Listenable.merge([nameController, instructionsController]),
          builder: (context, _) {
            final name = nameController.text.trim();
            final instructions = instructionsController.text.trim();
            final complete = name.isNotEmpty && instructions.isNotEmpty;
            return FilledButton(
              onPressed: complete
                  ? () => Navigator.of(dialogContext).pop((name, instructions))
                  : null,
              child: Text(isEdit ? 'Save' : 'Create'),
            );
          },
        ),
      ],
    ),
    // Both controllers outlive the builder, so the dialog closing is the only
    // point at which they can be disposed. Without this every visit to the
    // style editor leaks two ChangeNotifiers and their listeners.
  ).whenComplete(() {
    nameController.dispose();
    instructionsController.dispose();
  });
}
