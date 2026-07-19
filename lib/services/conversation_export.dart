import 'dart:convert';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'download_service.dart';

/// Renders a conversation for export. The markdown/json builders are pure
/// (unit-tested); the download wrappers hand off to [DownloadService].
class ConversationExport {
  ConversationExport._();

  static String toMarkdown(Conversation conversation) {
    final buffer = StringBuffer('# ${conversation.title}\n');
    buffer.writeln(
        '\n_Exported from SHIFT AI · ${conversation.updatedAt.toIso8601String()}_\n');
    for (final message in conversation.messages) {
      final role = switch (message.role) {
        MessageRole.user => 'You',
        MessageRole.assistant => 'SHIFT AI',
        MessageRole.system => 'System',
      };
      buffer.writeln('\n## $role\n');
      buffer.writeln(message.text);
      if (message.citations.isNotEmpty) {
        buffer.writeln('\nSources:');
        for (var i = 0; i < message.citations.length; i++) {
          final citation = message.citations[i];
          buffer.writeln('${i + 1}. [${citation.title}](${citation.url})');
        }
      }
    }
    if (conversation.artifacts.isNotEmpty) {
      buffer.writeln('\n---\n\n# Artifacts');
      for (final artifact in conversation.artifacts) {
        buffer.writeln(
            '\n## ${artifact.title} (v${artifact.versions.length})\n');
        buffer.writeln('```${artifact.language ?? artifact.kind.name}');
        buffer.writeln(artifact.latest.content);
        buffer.writeln('```');
      }
    }
    return buffer.toString();
  }

  static String toJsonString(Conversation conversation) =>
      const JsonEncoder.withIndent('  ').convert(conversation.toJson());

  static void downloadMarkdown(Conversation conversation) {
    DownloadService.downloadText(
      toMarkdown(conversation),
      '${DownloadService.slugify(conversation.title, fallback: 'conversation')}.md',
      mimeType: 'text/markdown;charset=utf-8',
    );
  }

  static void downloadJson(Conversation conversation) {
    DownloadService.downloadText(
      toJsonString(conversation),
      '${DownloadService.slugify(conversation.title, fallback: 'conversation')}.json',
      mimeType: 'application/json;charset=utf-8',
    );
  }
}
