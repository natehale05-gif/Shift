import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models/artifact.dart';
import '../../core/platform/download_service.dart';
import 'js_sandbox_service.dart';
import '../../core/state/artifact_panel_store.dart';
import '../../data/stores/conversation_store.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import 'artifact_code_view.dart';
import 'artifact_preview.dart';
import 'console_output_view.dart';

/// The artifacts side panel: serif title, Preview/Code tabs, version
/// stepper, copy/download, and a Run button (with console drawer) for
/// JavaScript artifacts.
class ArtifactPanel extends StatefulWidget {
  const ArtifactPanel({super.key});

  @override
  State<ArtifactPanel> createState() => _ArtifactPanelState();
}

class _ArtifactPanelState extends State<ArtifactPanel> {
  List<ConsoleLine>? _consoleLines;
  bool _running = false;

  static const _downloadExtensions = {
    ArtifactKind.html: 'html',
    ArtifactKind.svg: 'svg',
    ArtifactKind.markdown: 'md',
  };

  bool _isRunnable(Artifact artifact) =>
      artifact.kind == ArtifactKind.code &&
      const ['javascript', 'js', 'typescript']
          .contains(artifact.language?.toLowerCase());

  /// Highlighting language for the Code tab, by artifact kind.
  static String _codeLanguage(Artifact artifact) => switch (artifact.kind) {
        ArtifactKind.html => 'html',
        ArtifactKind.svg => 'xml',
        ArtifactKind.markdown => 'markdown',
        ArtifactKind.code => artifact.language ?? 'plaintext',
      };

  Future<void> _run(String code) async {
    setState(() {
      _running = true;
      _consoleLines = null;
    });
    final lines = await JsSandboxService.run(code);
    if (!mounted) return;
    setState(() {
      _running = false;
      _consoleLines = lines;
    });
  }

  void _download(Artifact artifact, String content) {
    final extension = _downloadExtensions[artifact.kind] ??
        (artifact.language ?? 'txt');
    final filename = artifact.title.contains('.')
        ? artifact.title
        : '${DownloadService.slugify(artifact.title)}.$extension';
    DownloadService.downloadText(content, filename);
  }

  @override
  Widget build(BuildContext context) {
    final panel = context.watch<ArtifactPanelStore>();
    final store = context.watch<ConversationStore>();
    final artifact = panel.artifactId != null
        ? store.current?.artifactById(panel.artifactId!)
        : null;

    if (artifact == null) {
      // Artifact belongs to another (or deleted) conversation — close on
      // next frame rather than render a broken panel.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<ArtifactPanelStore>().close();
      });
      return const SizedBox.shrink();
    }

    panel.clampVersion(artifact.versions.length);
    final versionIndex = panel.versionIndex;
    final content = artifact.versions[versionIndex].content;
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    // Code is viewable for website/app builds, but hidden for interactive
    // results (recipe/quiz/flashcards/checklist) — you asked for the thing,
    // not its source.
    final showCodeToggle = !artifact.interactive;
    final onCodeTab = showCodeToggle && panel.tab == ArtifactTab.code;
    final showToolbar =
        showCodeToggle || _isRunnable(artifact) || artifact.versions.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    artifact.title,
                    style: AppTypography.serifDisplay(
                      fontSize: 17,
                      color: theme.textTheme.titleLarge!.color!,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy contents',
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: content)),
                ),
                IconButton(
                  tooltip: 'Download',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => _download(artifact, content),
                ),
                IconButton(
                  tooltip: 'Close',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => context.read<ArtifactPanelStore>().close(),
                ),
              ],
            ),
          ),
          // Preview/Code toggle for website/app builds; interactive results
          // render only. The code stays downloadable from the header either way.
          if (showToolbar) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  if (showCodeToggle)
                    SegmentedButton<ArtifactTab>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ArtifactTab.preview,
                          label: Text('Preview'),
                          icon: Icon(Icons.visibility_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: ArtifactTab.code,
                          label: Text('Code'),
                          icon: Icon(Icons.code_rounded, size: 16),
                        ),
                      ],
                      selected: {panel.tab},
                      onSelectionChanged: (selection) => context
                          .read<ArtifactPanelStore>()
                          .selectTab(selection.first),
                    ),
                  const Spacer(),
                  if (_isRunnable(artifact))
                    TextButton.icon(
                      onPressed: _running ? null : () => _run(content),
                      icon: _running
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.6),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Run'),
                    ),
                  if (artifact.versions.length > 1)
                    _VersionStepper(
                      versionIndex: versionIndex,
                      versionCount: artifact.versions.length,
                      onSelect: (index) => context
                          .read<ArtifactPanelStore>()
                          .selectVersion(index),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Divider(height: 1, color: colors.border),
          Expanded(
            child: onCodeTab
                ? ArtifactCodeView(
                    code: content,
                    language: _codeLanguage(artifact),
                  )
                : ArtifactPreview(
                    artifact: artifact,
                    versionIndex: versionIndex,
                  ),
          ),
          if (_consoleLines != null) ...[
            Divider(height: 1, color: colors.border),
            ConsoleOutputView(lines: _consoleLines!),
          ],
        ],
      ),
    );
  }
}

class _VersionStepper extends StatelessWidget {
  final int versionIndex;
  final int versionCount;
  final ValueChanged<int> onSelect;

  const _VersionStepper({
    required this.versionIndex,
    required this.versionCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous version',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed:
              versionIndex > 0 ? () => onSelect(versionIndex - 1) : null,
        ),
        Text(
          'v${versionIndex + 1} / $versionCount',
          style: theme.textTheme.labelMedium,
        ),
        IconButton(
          tooltip: 'Next version',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: versionIndex < versionCount - 1
              ? () => onSelect(versionIndex + 1)
              : null,
        ),
      ],
    );
  }
}
