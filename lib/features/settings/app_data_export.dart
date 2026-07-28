import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../data/models/conversation.dart';
import '../../data/models/memory_entry.dart';
import '../../data/models/project.dart';
import '../../core/platform/download_service.dart';

/// Bundles everything the app stores for this user into one downloadable
/// .zip — the local stand-in for "export my data". No server is involved;
/// the archive is built in the browser and downloaded.
class AppDataExport {
  AppDataExport._();

  static Uint8List buildZip({
    required List<Conversation> conversations,
    required List<Project> projects,
    required Map<String, dynamic> preferences,
    required List<MemoryEntry> memory,
    bool memoryEnabled = true,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    final archive = Archive();

    void addJson(String name, Object data) {
      final bytes = utf8.encode(encoder.convert(data));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('conversations.json',
        conversations.map((c) => c.toJson()).toList());
    addJson('projects.json', projects.map((p) => p.toJson()).toList());
    addJson('preferences.json', preferences);
    addJson('memory.json', {
      'enabled': memoryEnabled,
      'entries': memory.map((e) => e.toJson()).toList(),
    });
    addJson('README.json', {
      'app': 'SHIFT AI',
      'exportedAt': DateTime.now().toIso8601String(),
      'note': 'All data is stored locally in your browser; this archive is a '
          'complete copy of it.',
    });

    return Uint8List.fromList(ZipEncoder().encode(archive) ?? const <int>[]);
  }

  static void download({
    required List<Conversation> conversations,
    required List<Project> projects,
    required Map<String, dynamic> preferences,
    required List<MemoryEntry> memory,
    bool memoryEnabled = true,
  }) {
    final bytes = buildZip(
      conversations: conversations,
      projects: projects,
      preferences: preferences,
      memory: memory,
      memoryEnabled: memoryEnabled,
    );
    DownloadService.downloadBytes(
      bytes,
      'shift-ai-data-export.zip',
      mimeType: 'application/zip',
    );
  }
}
