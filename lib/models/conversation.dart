import 'artifact.dart';
import 'chat_message.dart';

class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final bool starred;
  final bool pinned;
  final bool archived;

  /// Project this conversation belongs to (null = unfiled).
  final String? projectId;

  /// Artifacts created in this conversation, keyed into by
  /// [ArtifactRefBlock.artifactId]. Stored inline with the conversation so
  /// persistence stays a single JSON tree until IndexedDB storage lands.
  final List<Artifact> artifacts;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.starred = false,
    this.pinned = false,
    this.archived = false,
    this.projectId,
    this.artifacts = const [],
  });

  Artifact? artifactById(String artifactId) {
    for (final artifact in artifacts) {
      if (artifact.id == artifactId) return artifact;
    }
    return null;
  }

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    bool? starred,
    bool? pinned,
    bool? archived,
    Object? projectId = _unset,
    List<Artifact>? artifacts,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      starred: starred ?? this.starred,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      projectId:
          projectId == _unset ? this.projectId : projectId as String?,
      artifacts: artifacts ?? this.artifacts,
    );
  }

  static const _unset = Object();

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        starred: json['starred'] as bool? ?? false,
        pinned: json['pinned'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
        projectId: json['projectId'] as String?,
        artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
            .map((e) => Artifact.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'starred': starred,
        'pinned': pinned,
        'archived': archived,
        'projectId': projectId,
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
      };
}
