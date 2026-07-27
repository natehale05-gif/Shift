/// One durable fact SHIFT AI remembers about the user across conversations
/// (Claude's Memory). [enabled] lets the user keep a fact but mute it.
class MemoryEntry {
  final String id;
  final String text;
  final bool enabled;
  final DateTime createdAt;

  const MemoryEntry({
    required this.id,
    required this.text,
    this.enabled = true,
    required this.createdAt,
  });

  MemoryEntry copyWith({String? text, bool? enabled}) => MemoryEntry(
        id: id,
        text: text ?? this.text,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
      );

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
        id: json['id'] as String,
        text: json['text'] as String,
        enabled: json['enabled'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
      };
}
