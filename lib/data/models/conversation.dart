import 'artifact.dart';
import 'chat_message.dart';

/// Alternate continuations from one branch point (Claude's message editing):
/// [tails] are the message sequences that can follow the anchor, and [active]
/// is the one currently spliced into the conversation.
class ConversationBranchSet {
  final List<List<ChatMessage>> tails;
  final int active;

  const ConversationBranchSet({required this.tails, required this.active});

  int get length => tails.length;

  ConversationBranchSet copyWith({
    List<List<ChatMessage>>? tails,
    int? active,
  }) =>
      ConversationBranchSet(
        tails: tails ?? this.tails,
        active: active ?? this.active,
      );

  factory ConversationBranchSet.fromJson(Map<String, dynamic> json) =>
      ConversationBranchSet(
        active: json['active'] as int? ?? 0,
        tails: (json['tails'] as List<dynamic>? ?? const [])
            .map((tail) => (tail as List<dynamic>)
                .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'tails': tails
            .map((tail) => tail.map((m) => m.toJson()).toList())
            .toList(),
      };
}

class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final bool starred;

  /// Project this conversation belongs to (null = unfiled).
  final String? projectId;

  /// Artifacts created in this conversation, keyed into by
  /// [ArtifactRefBlock.artifactId]. Stored inline with the conversation so
  /// persistence stays a single JSON tree until IndexedDB storage lands.
  final List<Artifact> artifacts;

  /// Edit-branch history keyed by the anchor message id (the message before the
  /// branch point, or '' for the start of the conversation).
  final Map<String, ConversationBranchSet> branches;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.starred = false,
    this.projectId,
    this.artifacts = const [],
    this.branches = const {},
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
    Object? projectId = _unset,
    List<Artifact>? artifacts,
    Map<String, ConversationBranchSet>? branches,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      starred: starred ?? this.starred,
      projectId:
          projectId == _unset ? this.projectId : projectId as String?,
      artifacts: artifacts ?? this.artifacts,
      branches: branches ?? this.branches,
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
        projectId: json['projectId'] as String?,
        artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
            .map((e) => Artifact.fromJson(e as Map<String, dynamic>))
            .toList(),
        branches: (json['branches'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(
            k,
            ConversationBranchSet.fromJson(v as Map<String, dynamic>),
          ),
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'starred': starred,
        'projectId': projectId,
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
        if (branches.isNotEmpty)
          'branches': branches.map((k, v) => MapEntry(k, v.toJson())),
      };
}
