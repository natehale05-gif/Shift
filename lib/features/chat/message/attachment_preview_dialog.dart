import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/attachment.dart';
import '../../../services/download_service.dart';
import '../../../data/persistence/persistence_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class AttachmentPreviewDialog extends StatelessWidget {
  final Attachment attachment;
  final PersistenceService persistence;

  const AttachmentPreviewDialog({super.key, 
    required this.attachment,
    required this.persistence,
  });

  Future<Uint8List?> _load() async =>
      attachment.bytes ??
      (attachment.assetId != null
          ? persistence.loadAsset(attachment.assetId!)
          : null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(attachment.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () async {
                      final bytes = await _load();
                      if (bytes != null) {
                        DownloadService.downloadBytes(bytes, attachment.name,
                            mimeType: attachment.mimeType);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Flexible(
              child: FutureBuilder<Uint8List?>(
                future: _load(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text('This attachment is no longer stored.',
                          style: theme.textTheme.bodyMedium),
                    );
                  }
                  switch (attachment.kind) {
                    case AttachmentKind.image:
                      return InteractiveViewer(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      );
                    case AttachmentKind.text:
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: SelectableText(
                          utf8.decode(bytes, allowMalformed: true),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13, height: 1.5),
                        ),
                      );
                    case AttachmentKind.pdf:
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.picture_as_pdf_outlined,
                                size: 48, color: colors.textSecondary),
                            const SizedBox(height: AppSpacing.md),
                            Text('${(bytes.length / 1024).round()} KB PDF',
                                style: theme.textTheme.bodyMedium),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              onPressed: () => DownloadService.downloadBytes(
                                  bytes, attachment.name,
                                  mimeType: 'application/pdf'),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Download to view'),
                            ),
                          ],
                        ),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ‹1/2› switcher shown on an edited user message, stepping between the
/// alternate branches that follow from it.
