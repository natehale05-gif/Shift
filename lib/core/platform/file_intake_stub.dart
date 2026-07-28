import 'dart:typed_data';

/// Non-web fallback: no window-level paste/drop on this platform, so this is
/// a no-op that returns a disposer doing nothing.
void Function() registerFileIntake(
  void Function(String name, String mime, Uint8List bytes) onFile, {
  void Function(bool active)? onDragActive,
}) =>
    () {};
