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
    final multipleVersions = artifact.versions.length > 1;
    // Full-bleed when it owns the screen: a left border implies something to
    // the left of it.
    final fullScreen = panel.expanded || !_sideBySide(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: fullScreen
            ? null
            : Border(left: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        // Only meaningful once the panel covers the status bar, which is the
        // point of going full-screen on a phone.
        top: fullScreen,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One row, not two. Copy, download and run moved into the overflow
          // menu: they are things you do once, at the end, and each was
          // costing a permanent 40px of a screen whose whole job is showing
          // the artifact.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
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
                if (showCodeToggle)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: SegmentedButton<ArtifactTab>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ArtifactTab.preview,
                          label: Text('Preview'),
                        ),
                        ButtonSegment(
                          value: ArtifactTab.code,
                          label: Text('Code'),
                        ),
                      ],
                      selected: {panel.tab},
                      onSelectionChanged: (selection) => context
                          .read<ArtifactPanelStore>()
                          .selectTab(selection.first),
                    ),
                  ),
                _PanelMenu(
                  runnable: _isRunnable(artifact),
                  running: _running,
                  onRun: () => _run(content),
                  onCopy: () => Clipboard.setData(ClipboardData(text: content)),
                  onDownload: () => _download(artifact, content),
                ),
                if (_sideBySide(context))
                  IconButton(
                    tooltip: panel.expanded ? 'Exit full screen' : 'Full screen',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(panel.expanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded),
                    onPressed: () =>
                        context.read<ArtifactPanelStore>().toggleExpanded(),
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
          // Versions are the one control worth its own row, and only when
          // there is more than one to step between.
          if (multipleVersions) ...[
            Padding(
              padding:
                  const EdgeInsets.only(right: AppSpacing.sm, bottom: AppSpacing.xs),
              child: Align(
                alignment: Alignment.centerRight,
                child: _VersionStepper(
                  versionIndex: versionIndex,
                  versionCount: artifact.versions.length,
                  onSelect: (index) =>
                      context.read<ArtifactPanelStore>().selectVersion(index),
                ),
              ),
            ),
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
      ),
    );
  }

  /// Mirrors the chat screen's own threshold: below it the panel is always
  /// full-screen, so offering a full-screen toggle would be meaningless.
  static bool _sideBySide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 880;
}

/// Copy, download and run — the actions you reach for once, kept out of the
/// way of the thing you are looking at.
class _PanelMenu extends StatelessWidget {
  final bool runnable;
  final bool running;
  final VoidCallback onRun;
  final VoidCallback onCopy;
  final VoidCallback onDownload;

  const _PanelMenu({
    required this.runnable,
    required this.running,
    required this.onRun,
    required this.onCopy,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Artifact actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (value) => switch (value) {
        'copy' => onCopy(),
        'download' => onDownload(),
        'run' => running ? null : onRun(),
        _ => null,
      },
      itemBuilder: (context) => [
        if (runnable)
          const PopupMenuItem(
            value: 'run',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.play_arrow_rounded, size: 18),
              title: Text('Run'),
            ),
          ),
        const PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_rounded, size: 17),
            title: Text('Copy contents'),
          ),
        ),
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_rounded, size: 18),
            title: Text('Download'),
          ),
        ),
      ],
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
