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
/// [bytes] is the in-session copy. The bytes are also persisted to the
/// IndexedDB asset store keyed by [assetId] (mirrors generated images), so an
/// attachment's content survives a reload and can be previewed later.
class Attachment {
  final String id;
  final String name;
  final String mimeType;
  final AttachmentKind kind;
  final Uint8List? bytes;

  /// Key into the IndexedDB asset store holding this attachment's bytes.
  final String? assetId;

  const Attachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.kind,
    this.bytes,
    this.assetId,
  });

  int get sizeBytes => bytes?.length ?? 0;

  Attachment copyWith({Uint8List? bytes, String? assetId}) => Attachment(
        id: id,
        name: name,
        mimeType: mimeType,
        kind: kind,
        bytes: bytes ?? this.bytes,
        assetId: assetId ?? this.assetId,
      );

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        name: json['name'] as String,
        mimeType: json['mimeType'] as String,
        kind: AttachmentKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => AttachmentKind.text,
        ),
        assetId: json['assetId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'kind': kind.name,
        if (assetId != null) 'assetId': assetId,
        // bytes live in the asset store (see assetId), not inline.
      };
}
