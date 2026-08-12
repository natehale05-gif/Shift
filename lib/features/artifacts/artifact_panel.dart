import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/save_file.dart';
import '../../data/artifact.dart';
import 'artifact_code_view.dart';
import 'sandbox_view_stub.dart'
    if (dart.library.js_interop) 'sandbox_view_web.dart';

/// The deliverable, beside the conversation rather than inside it.
///
/// Everything here follows from one decision: a page is a *thing*, not a
/// message. It gets its own space, it keeps its previous versions, and it is
/// never made of chat text — before this, asking for a landing page filled the
/// transcript with several hundred lines of markup and the app's centrepiece
/// output was its worst.
///
/// Chrome is kept to one row on purpose. v1 grew to three (a title row, a
/// Preview/Code row, and a version row) and on a phone that left barely half
/// the screen for the thing being previewed.
class ArtifactPanel extends StatefulWidget {
  final Artifact artifact;

  /// Null on a wide window, where the panel is part of the layout rather than
  /// something opened over the conversation.
  final VoidCallback? onClose;

  const ArtifactPanel({super.key, required this.artifact, this.onClose});

  /// Wide enough for a page to look like a page. Narrower and the preview is
  /// a phone-shaped column that says nothing about how the page really reads.
  static const double width = 520;

  @override
  State<ArtifactPanel> createState() => _ArtifactPanelState();
}

class _ArtifactPanelState extends State<ArtifactPanel> {
  bool _showCode = false;
  int? _version;

  /// Defaults to the newest, and follows it when a revision arrives.
  ///
  /// v1 pinned the index and left the panel showing the version a revision had
  /// just replaced — so asking for a change and being shown the old page read
  /// as the change not landing.
  int get _index {
    final last = widget.artifact.versions.length - 1;
    final chosen = _version;
    return chosen == null || chosen > last ? last : chosen;
  }

  @override
  void didUpdateWidget(ArtifactPanel old) {
    super.didUpdateWidget(old);
    if (old.artifact.id != widget.artifact.id) {
      _version = null;
      _showCode = false;
    }
  }

  /// Writes the version being shown to a file the person chooses.
  ///
  /// Deferred out of N2b because there was no way to save anything off-web;
  /// there is now, and a page you can preview but not keep is a deliverable
  /// only in the sense that you can look at it.
  Future<void> _save(
    BuildContext context,
    Artifact artifact,
    ArtifactVersion version,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await saveFile(
      suggestedName: artifact.filename,
      bytes: Uint8List.fromList(utf8.encode(version.content)),
      mimeType: artifact.mimeType,
    );
    // Silent on a cancel: the person chose that, and an error there reads as
    // a failure they caused.
    if (saved) {
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final artifact = widget.artifact;
    final version = artifact.versions[_index];
    final showPreview = artifact.previewable && !_showCode;

    return Container(
      color: c.surface,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            _Chrome(
              artifact: artifact,
              index: _index,
              showCode: _showCode,
              onToggleCode: () => setState(() => _showCode = !_showCode),
              onVersion: (i) => setState(() => _version = i),
              onCopy: () =>
                  Clipboard.setData(ClipboardData(text: version.content)),
              // The version on screen, not the newest: someone looking at v1
              // and pressing Save expects v1.
              onSave: () => _save(context, artifact, version),
              onClose: widget.onClose,
            ),
            Divider(height: 1, thickness: 1, color: c.divider),
            Expanded(
              child: showPreview
                  // Keyed on the version, so stepping between them rebuilds
                  // the frame rather than showing the previous page's DOM.
                  ? buildSandboxedPreview(
                      viewKey: '${artifact.id}-$_index',
                      htmlContent: version.content,
                    )
                  : ArtifactCodeView(
                      code: version.content,
                      language: artifact.language,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  final Artifact artifact;
  final int index;
  final bool showCode;
  final VoidCallback onToggleCode;
  final ValueChanged<int> onVersion;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback? onClose;

  const _Chrome({
    required this.artifact,
    required this.index,
    required this.showCode,
    required this.onToggleCode,
    required this.onVersion,
    required this.onCopy,
    required this.onSave,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final many = artifact.versions.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
      child: Row(
        children: [
          if (onClose != null)
            _Icon(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Close',
              onTap: onClose!,
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: onClose == null ? 0 : Space.xxs),
              child: Text(
                artifact.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(color: c.text),
              ),
            ),
          ),

          // Only when there is more than one. A "v1 / 1" navigator is chrome
          // that can never be used, taking room from the thing it labels.
          if (many) ...[
            _Icon(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous version',
              onTap: index > 0 ? () => onVersion(index - 1) : null,
            ),
            Text('v${index + 1}/${artifact.versions.length}',
                style: text.labelSmall?.copyWith(color: c.textFaint)),
            _Icon(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next version',
              onTap: index < artifact.versions.length - 1
                  ? () => onVersion(index + 1)
                  : null,
            ),
          ],

          // Absent for something a browser cannot render: a Preview tab that
          // can only ever show source is a control that lies about having two
          // states.
          if (artifact.previewable)
            _Icon(
              icon: showCode ? Icons.visibility_outlined : Icons.code_rounded,
              tooltip: showCode ? 'Preview' : 'Code',
              onTap: onToggleCode,
            ),
          _Icon(
            icon: Icons.content_copy_rounded,
            tooltip: 'Copy',
            onTap: onCopy,
          ),
          // Absent where saving cannot work rather than present and inert:
          // `file_selector` has no iOS or Android implementation, so the
          // dialog never opens and the button does nothing at all.
          if (canSaveFile)
            _Icon(
              icon: Icons.download_rounded,
              tooltip: 'Save',
              onTap: onSave,
            ),
        ],
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _Icon({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          color: c.textMuted,
          disabledColor: c.textFaint,
        ),
      ),
    );
  }
}
