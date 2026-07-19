import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A lightweight text document attached to a project as always-available
/// context ("project knowledge"). Text-only so it persists fully in
/// localStorage.
class KnowledgeDoc {
  final String name;
  final String text;

  const KnowledgeDoc({required this.name, required this.text});

  factory KnowledgeDoc.fromJson(Map<String, dynamic> json) => KnowledgeDoc(
        name: json['name'] as String,
        text: json['text'] as String,
      );

  Map<String, dynamic> toJson() => {'name': name, 'text': text};
}

/// A workspace grouping conversations under shared custom instructions and
/// knowledge — Claude's Projects and Gemini's Gems in one concept (a "Gem"
/// is just a project whose instructions define a persona).
class Project {
  final String id;
  final String name;
  final String customInstructions;
  final List<KnowledgeDoc> knowledge;
  final int colorIndex;

  const Project({
    required this.id,
    required this.name,
    this.customInstructions = '',
    this.knowledge = const [],
    this.colorIndex = 0,
  });

  static const colors = [
    AppColors.accent,
    AppColors.systemIndigo,
    AppColors.systemBlue,
    AppColors.systemGreen,
    AppColors.systemOrange,
    AppColors.systemPurple,
  ];

  Color get color => colors[colorIndex % colors.length];

  Project copyWith({
    String? name,
    String? customInstructions,
    List<KnowledgeDoc>? knowledge,
    int? colorIndex,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      customInstructions: customInstructions ?? this.customInstructions,
      knowledge: knowledge ?? this.knowledge,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        customInstructions: json['customInstructions'] as String? ?? '',
        knowledge: (json['knowledge'] as List<dynamic>? ?? const [])
            .map((e) => KnowledgeDoc.fromJson(e as Map<String, dynamic>))
            .toList(),
        colorIndex: json['colorIndex'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'customInstructions': customInstructions,
        'knowledge': knowledge.map((e) => e.toJson()).toList(),
        'colorIndex': colorIndex,
      };
}
