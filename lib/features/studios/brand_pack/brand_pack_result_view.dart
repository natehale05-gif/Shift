


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/studio_result.dart';
import '../../../core/platform/download_service.dart';
import '../media/procedural_art.dart';
import '../shared/result_shell.dart';
import '../shared/studio_badge.dart';
import 'brand_pack_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BrandPackResultView extends StatefulWidget {
  final BrandPackResult result;
  const BrandPackResultView({super.key, required this.result});

  @override
  State<BrandPackResultView> createState() => _BrandPackResultViewState();
}


class _BrandPackResultViewState extends State<BrandPackResultView> {
  bool _building = false;

  Color _hex(String h) =>
      Color(int.parse(h.replaceFirst('#', ''), radix: 16) | 0xFF000000);

  Future<Uint8List> _logoBytes() async =>
      widget.result.logoPng ?? await rasterizeGradientArt(seed: widget.result.seed);

  Future<void> _download() async {
    setState(() => _building = true);
    final logo = await _logoBytes();
    final zip = BrandPackService.buildZip(widget.result, logo);
    if (mounted) setState(() => _building = false);
    final filename =
        '${DownloadService.slugify(widget.result.brandName, fallback: 'brand')}_pack.zip';
    DownloadService.downloadBytes(zip, filename, mimeType: 'application/zip');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final result = widget.result;
    return ResultShell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StudioBadge(text: result.live ? result.brandName : 'Draft · ${result.brandName}'),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _building ? null : _download,
                  icon: _building
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download kit (.zip)'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo tile.
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: SizedBox(
                    width: 72, height: 72,
                    child: result.logoPng != null
                        ? Image.memory(result.logoPng!, fit: BoxFit.cover)
                        : FutureBuilder<Uint8List>(
                            future: _logoBytes(),
                            builder: (context, snap) => snap.hasData
                                ? Image.memory(snap.data!, fit: BoxFit.cover)
                                : Container(color: colors.surfaceAlt),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Swatches + type.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final c in result.palette)
                            Container(
                              width: 28, height: 28,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _hex(c),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: colors.border),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('${result.headingFont} · ${result.bodyFont}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
