import 'attachment.dart';
import 'citation.dart';
import 'message_block.dart';
import 'studio_result.dart';
import 'studio_type.dart';
import 'usage_report.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, complete, incomplete, error }

/// Reader reaction to an assistant reply (Claude's thumbs up/down).
enum MessageFeedback { none, up, down }

/// A superseded assistant response kept when the user regenerates, so the
/// alternatives stay switchable behind a ‹1/2› navigator — the top-level
/// fields on [ChatMessage] hold the newest (live) response, and [variants]
/// holds the older snapshots.
class MessageVariant {
  final String text;
  final List<MessageBlock> blocks;
  final List<Citation> citations;
  final UsageReport? usage;
  final StudioResult? studioResult;

  const MessageVariant({
    required this.text,
    this.blocks = const [],
    this.citations = const [],
    this.usage,
    this.studioResult,
  });

  factory MessageVariant.fromJson(Map<String, dynamic> json) => MessageVariant(
        text: json['text'] as String? ?? '',
        blocks: (json['blocks'] as List<dynamic>? ?? const [])
            .map((e) => MessageBlock.fromJson(e as Map<String, dynamic>))
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
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'blocks': blocks.map((e) => e.toJson()).toList(),
        'citations': citations.map((e) => e.toJson()).toList(),
        'usage': usage?.toJson(),
        'studioResult': studioResult?.toJson(),
      };
}

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

  /// Older assistant responses kept across regenerations. The top-level fields
  /// above always hold the newest response; [variants] holds the previous ones.
  final List<MessageVariant> variants;

  /// Which response is on screen: an index into the virtual list
  /// `[...variants, live]`, so [variants].length points at the live one.
  final int activeVariant;

  final MessageFeedback feedback;

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
    this.variants = const [],
    this.activeVariant = 0,
    this.feedback = MessageFeedback.none,
  });

  /// True when there is more than one response to switch between.
  bool get hasVariants => variants.isNotEmpty;

  /// Total number of responses (older snapshots + the live one).
  int get variantCount => variants.length + 1;

  bool get _showingLive => activeVariant >= variants.length;

  String get displayText => _showingLive ? text : variants[activeVariant].text;
  List<MessageBlock> get displayBlocks =>
      _showingLive ? blocks : variants[activeVariant].blocks;
  List<Citation> get displayCitations =>
      _showingLive ? citations : variants[activeVariant].citations;
  UsageReport? get displayUsage =>
      _showingLive ? usage : variants[activeVariant].usage;
  StudioResult? get displayStudioResult =>
      _showingLive ? studioResult : variants[activeVariant].studioResult;

  /// Snapshots the current (live) response into a [MessageVariant] for
  /// archiving before a regeneration overwrites the top-level fields.
  MessageVariant toVariant() => MessageVariant(
        text: text,
        blocks: blocks,
        citations: citations,
        usage: usage,
        studioResult: studioResult,
      );

  ChatMessage copyWith({
    String? text,
    List<MessageBlock>? blocks,
    List<Attachment>? attachments,
    List<Citation>? citations,
    UsageReport? usage,
    StudioType? studioType,
    StudioResult? studioResult,
    MessageStatus? status,
    List<MessageVariant>? variants,
    int? activeVariant,
    MessageFeedback? feedback,
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
      variants: variants ?? this.variants,
      activeVariant: activeVariant ?? this.activeVariant,
      feedback: feedback ?? this.feedback,
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
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .map((e) => MessageVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeVariant: json['activeVariant'] as int? ?? 0,
      feedback: MessageFeedback.values.firstWhere(
        (e) => e.name == json['feedback'],
        orElse: () => MessageFeedback.none,
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
        if (variants.isNotEmpty)
          'variants': variants.map((e) => e.toJson()).toList(),
        if (activeVariant != 0) 'activeVariant': activeVariant,
        if (feedback != MessageFeedback.none) 'feedback': feedback.name,
      };
}
