// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Registers window-level **paste** and **drag-and-drop** file intake, so the
/// composer accepts a pasted screenshot or a dropped image/PDF/text file just
/// like Claude. [onFile] is called once per accepted file with its bytes;
/// [onDragActive] toggles as files are dragged over the window (for a drop
/// highlight). Returns a disposer that removes the listeners.
void Function() registerFileIntake(
  void Function(String name, String mime, Uint8List bytes) onFile, {
  void Function(bool active)? onDragActive,
}) {
  final subs = <StreamSubscription<dynamic>>[];

  bool accepted(String mime) =>
      mime.startsWith('image/') ||
      mime == 'application/pdf' ||
      mime.startsWith('text/');

  void readBlob(html.Blob blob, String name) {
    final mime = blob.type.isNotEmpty ? blob.type : 'application/octet-stream';
    if (!accepted(mime)) return;
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      final bytes = result is ByteBuffer
          ? result.asUint8List()
          : result is Uint8List
              ? result
              : null;
      if (bytes != null) onFile(name, mime, bytes);
    });
    reader.readAsArrayBuffer(blob);
  }

  // Paste: pull any file items out of the clipboard payload.
  subs.add(html.document.onPaste.listen((html.ClipboardEvent e) {
    final items = e.clipboardData?.items;
    if (items == null) return;
    final count = items.length ?? 0;
    for (var i = 0; i < count; i++) {
      final item = items[i];
      if (item.kind != 'file') continue;
      final file = item.getAsFile();
      if (file == null) continue;
      final name = file.name.isNotEmpty
          ? file.name
          : 'pasted-${DateTime.now().millisecondsSinceEpoch}.png';
      readBlob(file, name);
    }
  }));

  // Drag-and-drop: preventDefault so the browser doesn't navigate away, and
  // read the dropped files.
  subs.add(html.document.onDragOver.listen((html.MouseEvent e) {
    e.preventDefault();
    onDragActive?.call(true);
  }));
  subs.add(html.document.onDragLeave.listen((html.MouseEvent e) {
    e.preventDefault();
    onDragActive?.call(false);
  }));
  subs.add(html.document.onDrop.listen((html.MouseEvent e) {
    e.preventDefault();
    onDragActive?.call(false);
    final files = e.dataTransfer.files;
    if (files == null) return;
    for (final file in files) {
      readBlob(file, file.name);
    }
  }));

  return () {
    for (final s in subs) {
      s.cancel();
    }
  };
}
