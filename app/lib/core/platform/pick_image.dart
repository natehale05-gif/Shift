import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// A picture the person chose from their own files.
typedef PickedImage = ({String name, Uint8List bytes, String mimeType});

/// The formats a provider will accept as an input picture.
///
/// Filtered at the dialog rather than after it, so a `.heic` off an iPhone is
/// not offered and then refused — which would read as the app being broken
/// rather than as a format it cannot send.
const _kinds = <XTypeGroup>[
  XTypeGroup(
    label: 'Pictures',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
  ),
];

/// The most a picture may weigh before it is refused.
///
/// It travels to the provider base64-encoded, which is a third larger again,
/// and a 40 MB photo is a request that will time out rather than answer. The
/// number is a judgement, not a provider limit — it is the size above which
/// waiting stops being worth it.
const kMaxPictureBytes = 12 * 1024 * 1024;

/// What came back from the picker.
///
/// Three outcomes, not two. Cancelling and being refused both produce no
/// picture, and collapsing them into one null would mean either saying nothing
/// when a file was rejected — the picker just closing, which reads as the app
/// being broken — or apologising to someone who pressed Cancel on purpose.
typedef PickResult = ({PickedImage? image, String? refused});

/// Opens the file picker.
Future<PickResult> pickImage() async {
  final file = await openFile(acceptedTypeGroups: _kinds);
  if (file == null) return (image: null, refused: null);

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return (image: null, refused: 'That file is empty.');
  }
  if (bytes.length > kMaxPictureBytes) {
    return (
      image: null,
      refused: 'That picture is over '
          '${kMaxPictureBytes ~/ (1024 * 1024)} MB, which is more than a '
          'provider will take. A smaller copy will work.',
    );
  }

  return (
    image: (
      name: file.name,
      bytes: bytes,
      mimeType: mimeTypeFor(file.name, file.mimeType),
    ),
    refused: null,
  );
}

/// What to tell a provider this picture is.
///
/// The picker reports a MIME type on some platforms and not others, and the
/// extension is the only thing available everywhere. A wrong type here is a
/// provider rejecting a valid picture, so the extension wins when it is
/// recognised: it comes from the file itself rather than from a plugin's
/// best guess.
String mimeTypeFor(String name, [String? reported]) {
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    _ => reported ?? 'image/png',
  };
}
