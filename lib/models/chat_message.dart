import 'studio_result.dart';
import 'studio_type.dart';

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, complete, error }

class ChatMessage {
  final String id;
  final String conversationId;
  final MessageRole role;
  final StudioType? studioType;
  final String text;
  final StudioResult? studioResult;
  final DateTime timestamp;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    this.studioType,
    this.studioResult,
    required this.timestamp,
    this.status = MessageStatus.complete,
  });

  ChatMessage copyWith({
    String? text,
    StudioType? studioType,
    StudioResult? studioResult,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      text: text ?? this.text,
      studioType: studioType ?? this.studioType,
      studioResult: studioResult ?? this.studioResult,
      timestamp: timestamp,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        role: MessageRole.values.firstWhere((e) => e.name == json['role']),
        studioType: json['studioType'] != null
            ? StudioType.fromName(json['studioType'] as String)
            : null,
        text: json['text'] as String,
        studioResult: json['studioResult'] != null
            ? StudioResult.fromJson(
                json['studioResult'] as Map<String, dynamic>)
            : null,
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: MessageStatus.values
            .firstWhere((e) => e.name == json['status'], orElse: () => MessageStatus.complete),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'role': role.name,
        'studioType': studioType?.name,
        'text': text,
        'studioResult': studioResult?.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
      };
}
