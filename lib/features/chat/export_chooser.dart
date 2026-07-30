import 'package:flutter/material.dart';

import '../../data/models/conversation.dart';
import 'conversation_export.dart';

/// Asks which format, then exports.
///
/// The menu used to carry three entries — Markdown, JSON, PDF — which is one
/// verb offered three times. The format is a detail of the export, not three
/// different things to do, and three of seven items in a menu saying the same
/// word makes the other four harder to find.
Future<void> showExportChooser(
  BuildContext context,
  Conversation conversation,
) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Export "${conversation.title}"',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          for (final option in exportFormats)
            ListTile(
              leading: Icon(option.icon),
              title: Text(option.label),
              subtitle: Text(option.detail),
              onTap: () => Navigator.of(context).pop(option.id),
            ),
        ],
      ),
    ),
  );
  if (format == null) return;
  switch (format) {
    case 'markdown':
      ConversationExport.downloadMarkdown(conversation);
    case 'json':
      ConversationExport.downloadJson(conversation);
    case 'pdf':
      ConversationExport.exportPdf(conversation);
  }
}

/// One format the chooser offers.
class ExportFormat {
  final String id;
  final String label;
  final String detail;
  final IconData icon;
  const ExportFormat(this.id, this.label, this.detail, this.icon);
}

/// The formats, as data — so the sheet and any test read the same list rather
/// than each carrying its own copy.
const List<ExportFormat> exportFormats = [
  ExportFormat('markdown', 'Markdown', 'Plain text you can paste anywhere',
      Icons.notes_rounded),
  ExportFormat('json', 'JSON', 'Every message and artifact, for re-importing',
      Icons.data_object_rounded),
  ExportFormat('pdf', 'PDF', 'A printable copy of the transcript',
      Icons.picture_as_pdf_outlined),
];
