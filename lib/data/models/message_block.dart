import 'dart:convert';
import 'dart:typed_data';

import 'artifact.dart';

/// One ordered piece of an assistant message. Real assistant turns are a
/// sequence of blocks — thinking, tool activity, prose, images, artifact
/// references — rendered in order.
sealed class MessageBlock {
  const MessageBlock();

  Map<String, dynamic> toJson();

  static MessageBlock fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'text' => TextBlock(json['text'] as String),
      'thinking' => ThinkingBlock(json['text'] as String),
      'toolUse' => ToolUseBlock(
          id: json['id'] as String,
          tool: json['tool'] as String,
          label: json['label'] as String,
          status: ToolUseStatus.values.firstWhere(
            (e) => e.name == json['status'],
            orElse: () => ToolUseStatus.done,
          ),
          detail: json['detail'] as String?,
        ),
      'image' => ImageBlock(
          alt: json['alt'] as String,
          assetId: json['assetId'] as String?,
          pngBytes: json['pngBase64'] != null
              ? base64Decode(json['pngBase64'] as String)
              : null,
        ),
      'choice' => ChoiceBlock(
          id: json['id'] as String,
          question: json['question'] as String,
          options: (json['options'] as List<dynamic>).cast<String>(),
          multiSelect: json['multiSelect'] as bool? ?? false,
          chosen: (json['chosen'] as List<dynamic>? ?? const []).cast<String>(),
        ),
      'artifactRef' => ArtifactRefBlock(
          artifactId: json['artifactId'] as String,
          title: json['title'] as String,
          kind: ArtifactKind.fromName(json['kind'] as String),
          versionIndex: json['versionIndex'] as int,
          interactive: json['interactive'] as bool? ?? false,
        ),
      _ => TextBlock(json['text'] as String? ?? ''),
    };
  }
}

class TextBlock extends MessageBlock {
  final String text;
  const TextBlock(this.text);

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

/// The model's (summarized) reasoning, shown behind a collapsed disclosure.
class ThinkingBlock extends MessageBlock {
  final String text;
  const ThinkingBlock(this.text);

  @override
  Map<String, dynamic> toJson() => {'type': 'thinking', 'text': text};
}

enum ToolUseStatus { running, done, failed }

class ToolUseBlock extends MessageBlock {
  final String id;

  /// Machine name, e.g. 'web_search', 'code_execution', 'deep_research'.
  final String tool;

  /// Human label shown in the chip, e.g. 'Searching the web…'.
  final String label;
  final ToolUseStatus status;

  /// Result summary once finished (e.g. '5 sources', stdout excerpt).
  final String? detail;

  const ToolUseBlock({
    required this.id,
    required this.tool,
    required this.label,
    required this.status,
    this.detail,
  });

  ToolUseBlock copyWith({
    String? label,
    ToolUseStatus? status,
    String? detail,
  }) =>
      ToolUseBlock(
        id: id,
        tool: tool,
        label: label ?? this.label,
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'toolUse',
        'id': id,
        'tool': tool,
        'label': label,
        'status': status.name,
        'detail': detail,
      };
}

/// A generated image. The persisted JSON stores only [assetId] — the bytes
/// live in the IndexedDB asset store and are rehydrated lazily when the
/// block renders. [pngBytes] is the in-memory copy from the session that
/// generated the image.
class ImageBlock extends MessageBlock {
  final String alt;
  final Uint8List? pngBytes;
  final String? assetId;

  const ImageBlock({required this.alt, this.pngBytes, this.assetId});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image',
        'alt': alt,
        'assetId': assetId,
        // Raw bytes intentionally omitted — see class doc.
      };
}

/// A question the assistant is asking, offered as tappable options rather than
/// as a paragraph inviting the user to type one back.
///
/// [chosen] is empty while the question is live and holds the answer once it
/// has been given — which is what makes it survive a reload as an *answered*
/// question. A question that re-armed itself on reopen would invite answering
/// it twice, and the second answer would arrive with no memory of the first.
class ChoiceBlock extends MessageBlock {
  /// Distinguishes this question from any other in the same message, so an
  /// answer can be matched to the question it belongs to.
  final String id;
  final String question;
  final List<String> options;
  final bool multiSelect;
  final List<String> chosen;

  const ChoiceBlock({
    required this.id,
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.chosen = const [],
  });

  bool get answered => chosen.isNotEmpty;

  ChoiceBlock withChoice(List<String> picked) => ChoiceBlock(
        id: id,
        question: question,
        options: options,
        multiSelect: multiSelect,
        chosen: picked,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'choice',
        'id': id,
        'question': question,
        'options': options,
        'multiSelect': multiSelect,
        'chosen': chosen,
      };
}

/// Pointer from a message to an artifact version created/updated by that
/// turn. Non-interactive artifacts (websites/apps) render as a tappable card
/// that opens the side panel; [interactive] ones (recipe/quiz/flashcards/
/// checklist) render as a live widget inline in the conversation, like Claude.
class ArtifactRefBlock extends MessageBlock {
  final String artifactId;
  final String title;
  final ArtifactKind kind;
  final int versionIndex;
  final bool interactive;

  const ArtifactRefBlock({
    required this.artifactId,
    required this.title,
    required this.kind,
    required this.versionIndex,
    this.interactive = false,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'artifactRef',
        'artifactId': artifactId,
        'title': title,
        'kind': kind.name,
        'versionIndex': versionIndex,
        if (interactive) 'interactive': true,
      };
}
