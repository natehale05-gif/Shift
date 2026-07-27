import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/attachment.dart';
import '../../../services/web/file_intake.dart';

const _uuid = Uuid();

/// The files staged on the composer for the next turn, and the three ways they
/// get there: the attach button, a paste, or a drop anywhere in the window.
///
/// Owns the window-level paste/drop listener lifecycle, which is the part that
/// leaks if it is left tangled in the widget's State.
class ComposerAttachments {
  final List<Attachment> items = [];

  /// True while files are being dragged over the window (drop highlight).
  bool dragActive = false;

  void Function()? _disposeIntake;

  /// Starts listening for pasted screenshots and dropped files. [onChanged]
  /// fires whenever the staged list or [dragActive] changes, so the composer
  /// can repaint.
  void startIntake(void Function() onChanged) {
    _disposeIntake = registerFileIntake(
      (name, mime, bytes) {
        items.add(Attachment(
          id: _uuid.v4(),
          name: name,
          mimeType: mime,
          kind: AttachmentKind.fromMimeType(mime),
          bytes: bytes,
        ));
        onChanged();
      },
      onDragActive: (active) {
        if (active != dragActive) {
          dragActive = active;
          onChanged();
        }
      },
    );
  }

  /// Opens the system file picker and stages whatever is chosen.
  Future<void> pickFiles() async {
    const typeGroup = XTypeGroup(
      label: 'Images, PDFs & text',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'txt', 'md'],
    );
    final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final mimeType = file.mimeType ?? mimeFromName(file.name);
      items.add(Attachment(
        id: _uuid.v4(),
        name: file.name,
        mimeType: mimeType,
        kind: AttachmentKind.fromMimeType(mimeType),
        bytes: bytes,
      ));
    }
  }

  /// Best-effort MIME from a filename, for pickers that don't report one.
  static String mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      _ => 'text/plain',
    };
  }

  /// A copy of the staged files, for handing to a turn before clearing.
  List<Attachment> snapshot() => List.of(items);

  void clear() => items.clear();

  void dispose() {
    _disposeIntake?.call();
    _disposeIntake = null;
  }
}
