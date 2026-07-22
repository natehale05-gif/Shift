import 'dart:convert';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'download_service.dart';
import 'web/print_service.dart';

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

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// A printable HTML rendering of the conversation (used for Export as PDF via
  /// the browser print dialog). Pure so it's unit-testable.
  static String toPrintableHtml(Conversation conversation) {
    final buffer = StringBuffer('<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<title>${_esc(conversation.title)}</title><style>'
        'body{font-family:Georgia,serif;max-width:720px;margin:32px auto;'
        'padding:0 16px;color:#1c1c1e;line-height:1.6;}'
        'h1{font-size:24px;} .role{font-weight:700;margin-top:24px;'
        'font-family:system-ui,sans-serif;font-size:13px;color:#666;'
        'text-transform:uppercase;letter-spacing:.5px;}'
        '.msg{white-space:pre-wrap;}'
        '</style></head><body>');
    buffer.write('<h1>${_esc(conversation.title)}</h1>');
    for (final message in conversation.messages) {
      if (message.role == MessageRole.system) continue;
      final role = message.role == MessageRole.user ? 'You' : 'SHIFT AI';
      buffer.write('<div class="role">${_esc(role)}</div>');
      buffer.write('<div class="msg">${_esc(message.displayText)}</div>');
    }
    buffer.write('</body></html>');
    return buffer.toString();
  }

  /// Opens the browser print dialog for the conversation (Save as PDF).
  static void exportPdf(Conversation conversation) {
    printHtmlDocument(toPrintableHtml(conversation));
  }
}
