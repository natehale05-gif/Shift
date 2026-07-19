import 'artifact.dart';
import 'chat_message.dart';

class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final bool starred;

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
    List<Artifact>? artifacts,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      starred: starred ?? this.starred,
      artifacts: artifacts ?? this.artifacts,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        starred: json['starred'] as bool? ?? false,
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
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
      };
}
