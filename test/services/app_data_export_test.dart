import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/memory_entry.dart';
import 'package:shift_ai/data/models/project.dart';
import 'package:shift_ai/features/settings/app_data_export.dart';

void main() {
  test('buildZip produces a valid archive with all data parts', () {
    final bytes = AppDataExport.buildZip(
      conversations: [
        Conversation(
          id: 'c1',
          title: 'Kyoto trip',
          createdAt: DateTime(2026, 7, 20),
          updatedAt: DateTime(2026, 7, 21),
        ),
      ],
      projects: [Project(id: 'p1', name: 'Launch', colorIndex: 0)],
      preferences: const {'nickname': 'Nate', 'responseStyle': 'formal'},
      memory: [
        MemoryEntry(
          id: 'm1',
          text: 'Lives in Kyoto',
          createdAt: DateTime(2026, 7, 21),
        ),
      ],
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'conversations.json',
        'projects.json',
        'preferences.json',
        'memory.json',
        'README.json',
      ]),
    );

    // The conversation round-trips through the archive.
    final convoFile =
        archive.files.firstWhere((f) => f.name == 'conversations.json');
    final decoded =
        jsonDecode(utf8.decode(convoFile.content as List<int>)) as List;
    expect((decoded.first as Map)['title'], 'Kyoto trip');

    final memFile = archive.files.firstWhere((f) => f.name == 'memory.json');
    final mem = jsonDecode(utf8.decode(memFile.content as List<int>)) as Map;
    expect((mem['entries'] as List).first['text'], 'Lives in Kyoto');
  });
}
