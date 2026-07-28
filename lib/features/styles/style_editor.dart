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
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            final instructions = instructionsController.text.trim();
            if (name.isEmpty || instructions.isEmpty) return;
            Navigator.of(dialogContext).pop((name, instructions));
          },
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    ),
  );
}
