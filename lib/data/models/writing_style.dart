/// A user-created response style (Claude's custom styles): a name plus the
/// instructions folded into the system prompt when the style is active.
class WritingStyle {
  final String id;
  final String name;
  final String instructions;

  const WritingStyle({
    required this.id,
    required this.name,
    required this.instructions,
  });

  WritingStyle copyWith({String? name, String? instructions}) => WritingStyle(
        id: id,
        name: name ?? this.name,
        instructions: instructions ?? this.instructions,
      );

  factory WritingStyle.fromJson(Map<String, dynamic> json) => WritingStyle(
        id: json['id'] as String,
        name: json['name'] as String,
        instructions: json['instructions'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'instructions': instructions,
      };
}
