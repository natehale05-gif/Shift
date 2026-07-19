import 'dart:typed_data';

enum AttachmentKind {
  image,
  pdf,
  text;

  static AttachmentKind fromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return AttachmentKind.image;
    if (mimeType == 'application/pdf') return AttachmentKind.pdf;
    return AttachmentKind.text;
  }
}

/// A file the user attached to a message (image, PDF, or plain text).
///
/// [bytes] lives in memory for the current session only. Until IndexedDB
/// storage lands, persisted JSON records just the metadata — reloading the
/// app shows the attachment's name but not its content, keeping big base64
/// blobs out of the ~5MB localStorage quota.
class Attachment {
  final String id;
  final String name;
  final String mimeType;
  final AttachmentKind kind;
  final Uint8List? bytes;

  const Attachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.kind,
    this.bytes,
  });

  int get sizeBytes => bytes?.length ?? 0;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        name: json['name'] as String,
        mimeType: json['mimeType'] as String,
        kind: AttachmentKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => AttachmentKind.text,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'kind': kind.name,
        // bytes intentionally omitted — see class doc.
      };
}
