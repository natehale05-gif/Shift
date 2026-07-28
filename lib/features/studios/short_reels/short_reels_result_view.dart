


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../media/procedural_art.dart';
import '../shared/result_shell.dart';
import '../shared/studio_badge.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'short_reels_service.dart';

class ShortReelsResultView extends StatefulWidget {
  final ShortReelsPackResult result;
  const ShortReelsResultView({super.key, required this.result});

  @override
  State<ShortReelsResultView> createState() => _ShortReelsResultViewState();
}


class _ShortReelsResultViewState extends State<ShortReelsResultView> {
  bool _building = false;

  Future<List<Uint8List>> _posters() => Future.wait(
      widget.result.reels.map((r) => rasterizeGradientArt(seed: r.seed)));

  Future<void> _download() async {
    setState(() => _building = true);
    final posters = await _posters();
    final zip = ShortReelsService.buildZip(widget.result, posters);
    if (mounted) setState(() => _building = false);
    final filename =
        '${DownloadService.slugify(widget.result.topic, fallback: 'reels')}_pack.zip';
    DownloadService.downloadBytes(zip, filename, mimeType: 'application/zip');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final reels = widget.result.reels;
    return ResultShell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StudioBadge(
                    text: widget.result.live
                        ? '${reels.length} reels'
                        : 'Draft · ${reels.length} reels'),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _building ? null : _download,
                  icon: _building
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download pack (.zip)'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // A row of 9:16 poster thumbnails.
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reels.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: SizedBox(
                    width: 74,
                    child: FutureBuilder<Uint8List>(
                      future: rasterizeGradientArt(seed: reels[i].seed),
                      builder: (context, snap) => snap.hasData
                          ? Image.memory(snap.data!, fit: BoxFit.cover)
                          : Container(color: colors.surfaceAlt),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final r in reels)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${r.hook}',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
