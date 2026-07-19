import 'attachment.dart';
import 'citation.dart';
import 'message_block.dart';
import 'studio_result.dart';
import 'studio_type.dart';
import 'usage_report.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, complete, error }

class ChatMessage {
  final String id;
  final String conversationId;
  final MessageRole role;
  final StudioType? studioType;

  /// Flat text of the message. For assistant turns this mirrors the
  /// concatenated [TextBlock]s (kept in sync by the store) so copy, search,
  /// and titles never need to walk blocks.
  final String text;

  /// Ordered content blocks for assistant turns. Empty for user turns.
  final List<MessageBlock> blocks;

  /// Files the user attached to this (user) turn.
  final List<Attachment> attachments;

  /// Web sources backing this (assistant) turn.
  final List<Citation> citations;

  final UsageReport? usage;
  final StudioResult? studioResult;
  final DateTime timestamp;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    this.blocks = const [],
    this.attachments = const [],
    this.citations = const [],
    this.usage,
    this.studioType,
    this.studioResult,
    required this.timestamp,
    this.status = MessageStatus.complete,
  });

  ChatMessage copyWith({
    String? text,
    List<MessageBlock>? blocks,
    List<Attachment>? attachments,
    List<Citation>? citations,
    UsageReport? usage,
    StudioType? studioType,
    StudioResult? studioResult,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      text: text ?? this.text,
      blocks: blocks ?? this.blocks,
      attachments: attachments ?? this.attachments,
      citations: citations ?? this.citations,
      usage: usage ?? this.usage,
      studioType: studioType ?? this.studioType,
      studioResult: studioResult ?? this.studioResult,
      timestamp: timestamp,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String;
    final role = MessageRole.values.firstWhere((e) => e.name == json['role']);
    // v1 records predate blocks: reconstruct a single text block so old
    // assistant messages render through the same block pipeline.
    final blocks = json['blocks'] != null
        ? (json['blocks'] as List<dynamic>)
            .map((e) => MessageBlock.fromJson(e as Map<String, dynamic>))
            .toList()
        : (role == MessageRole.assistant && text.isNotEmpty
            ? <MessageBlock>[TextBlock(text)]
            : const <MessageBlock>[]);
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      role: role,
      studioType: json['studioType'] != null
          ? StudioType.fromName(json['studioType'] as String)
          : null,
      text: text,
      blocks: blocks,
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      citations: (json['citations'] as List<dynamic>? ?? const [])
          .map((e) => Citation.fromJson(e as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? UsageReport.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      studioResult: json['studioResult'] != null
          ? StudioResult.fromJson(json['studioResult'] as Map<String, dynamic>)
          : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.complete,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'role': role.name,
        'studioType': studioType?.name,
        'text': text,
        'blocks': blocks.map((e) => e.toJson()).toList(),
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'citations': citations.map((e) => e.toJson()).toList(),
        'usage': usage?.toJson(),
        'studioResult': studioResult?.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
      };
}
