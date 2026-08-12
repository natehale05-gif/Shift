import '../turn/request_title.dart';

/// One picture the app made, minus the picture.
///
/// Everything here is small enough to hold every one of them in memory at
/// once, which is what the gallery needs. The bytes are fetched by [id] from
/// the asset store only when something is actually going to draw them.
///
/// The prompt, provider and model travel with the image on purpose. An image
/// with no record of what made it cannot be regenerated, varied, or explained
/// six months later — and those are the three things anyone wants from a
/// picture they like.
/// Where a picture came from.
enum ImageOrigin {
  /// The app made it from a prompt.
  made,

  /// The person brought it. Kept apart because the two are treated
  /// differently by everything that reads a picture's history: an attached
  /// photo has no prompt to copy, cannot be regenerated, and its [prompt]
  /// field holds a filename rather than a description.
  attached;

  static ImageOrigin fromName(String? name) => ImageOrigin.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ImageOrigin.made,
      );
}

class MadeImage {
  final String id;

  /// What it was asked to be — or, for an [ImageOrigin.attached] picture, the
  /// name of the file it came from. One field rather than two because every
  /// reader wants the same thing from it: a short line naming this picture.
  final String prompt;
  final String provider;
  final String model;
  final String mimeType;
  final DateTime createdAt;

  /// The conversation it was made in, when it was made in one. Null for an
  /// image made straight from the gallery, which has no transcript behind it.
  final String? conversationId;

  final ImageOrigin origin;

  const MadeImage({
    required this.id,
    required this.prompt,
    required this.provider,
    required this.model,
    required this.mimeType,
    required this.createdAt,
    this.conversationId,
    this.origin = ImageOrigin.made,
  });

  /// The name it downloads as. Derived rather than stored, so a rule change
  /// reaches images made by an earlier build.
  ///
  /// Through [titleFromRequest] first, and that is the whole point: cutting
  /// the raw prompt at six words turns "make me a picture of a sunset over
  /// water" into `make-me-a-picture-of-a.png`, which names the request and
  /// drops the subject. Stripping the preamble leaves the six words that say
  /// what the picture *is*. Exactly the defect v1 fixed once and this
  /// rediscovered by looking at a real save dialog.
  String get filename {
    // An attached picture already has a name and it is the one the person
    // recognises. Running it through the request-title rule would turn
    // `holiday-2019.jpg` into something the app invented.
    if (origin == ImageOrigin.attached && prompt.contains('.')) return prompt;

    final words = titleFromRequest(prompt, fallback: 'image')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(6)
        .join('-');
    final stem = words.isEmpty ? 'image' : words;
    return '$stem.${mimeType == 'image/jpeg' ? 'jpg' : 'png'}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'provider': provider,
        'model': model,
        'mimeType': mimeType,
        'createdAt': createdAt.toIso8601String(),
        if (conversationId != null) 'conversationId': conversationId,
        // Written only when it is not the default, so a picture stored by an
        // earlier build reads back as what it was.
        if (origin != ImageOrigin.made) 'origin': origin.name,
      };

  static MadeImage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final created = DateTime.tryParse('${raw['createdAt']}');
    if (id is! String || id.isEmpty || created == null) return null;
    return MadeImage(
      id: id,
      prompt: raw['prompt'] is String ? raw['prompt'] as String : '',
      provider: raw['provider'] is String ? raw['provider'] as String : '',
      model: raw['model'] is String ? raw['model'] as String : '',
      mimeType:
          raw['mimeType'] is String ? raw['mimeType'] as String : 'image/png',
      createdAt: created,
      conversationId:
          raw['conversationId'] is String ? raw['conversationId'] as String : null,
      origin: ImageOrigin.fromName(raw['origin'] as String?),
    );
  }
}
