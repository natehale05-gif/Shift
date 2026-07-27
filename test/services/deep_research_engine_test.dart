import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/citation.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/deep_research_engine.dart';

ResearchRoundResult _round(String query) => ResearchRoundResult(
      notes: 'notes for $query',
      citations: [
        Citation(url: 'https://s.test/$query', title: 'Source $query'),
      ],
    );

void main() {
  test('walks planning → rounds → synthesis and ships a cited artifact',
      () async {
    final searched = <String>[];
    final engine = DeepResearchEngine(
      planQueries: (_) async => ['q1', 'q2'],
      search: (query) async {
        searched.add(query);
        return _round(query);
      },
      synthesize: (topic, notes) async => '# Report on $topic\n\nBody.',
    );

    final events =
        await engine.run(topic: 'solar', conversationId: 'c1').toList();

    final stages = events
        .whereType<DeepResearchProgress>()
        .map((e) => e.stage)
        .toList();
    expect(stages, ['planning', 'searching', 'searching', 'synthesizing']);
    expect(searched, ['q1', 'q2']);

    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.kind, ArtifactKind.markdown);
    expect(artifact.latest.content, contains('# Report on solar'));
    expect(artifact.latest.content, contains('## Sources'));
    expect(artifact.latest.content,
        contains('1. [Source q1](https://s.test/q1)'));
    expect(events.whereType<CitationsReady>().single.citations,
        hasLength(2));
  });

  test('caps rounds at maxRounds', () async {
    var searches = 0;
    final engine = DeepResearchEngine(
      planQueries: (_) async => List.generate(10, (i) => 'q$i'),
      search: (query) async {
        searches++;
        return _round(query);
      },
      synthesize: (_, __) async => 'report',
      maxRounds: 3,
    );
    await engine.run(topic: 't', conversationId: 'c1').drain<void>();
    expect(searches, 3);
  });

  test('a failed round is tolerated; the run still synthesizes', () async {
    final engine = DeepResearchEngine(
      planQueries: (_) async => ['good', 'bad', 'also-good'],
      search: (query) async {
        if (query == 'bad') throw Exception('network blip');
        return _round(query);
      },
      synthesize: (_, notes) async {
        expect(notes, contains('(search failed)'));
        return 'report';
      },
    );
    final events =
        await engine.run(topic: 't', conversationId: 'c1').toList();
    expect(events.whereType<MessageError>(), isEmpty);
    expect(events.whereType<ArtifactCreated>(), hasLength(1));
    expect(events.whereType<CitationsReady>().single.citations,
        hasLength(2));
  });

  test('cancel between rounds stops searching but still reports', () async {
    late DeepResearchEngine engine;
    var searches = 0;
    engine = DeepResearchEngine(
      planQueries: (_) async => ['q1', 'q2', 'q3'],
      search: (query) async {
        searches++;
        engine.cancel(); // cancel after the first round completes
        return _round(query);
      },
      synthesize: (_, __) async => 'partial report',
    );
    final events =
        await engine.run(topic: 't', conversationId: 'c1').toList();
    expect(searches, 1);
    expect(events.whereType<ArtifactCreated>(), hasLength(1));
    expect(
      events.whereType<MessageDelta>().map((e) => e.chunk).join(),
      contains('Stopped early'),
    );
  });

  test('all rounds failing produces an error, not an empty report',
      () async {
    final engine = DeepResearchEngine(
      planQueries: (_) async => ['q1'],
      search: (_) async => throw Exception('down'),
      synthesize: (_, __) async => fail('should not synthesize'),
    );
    final events =
        await engine.run(topic: 't', conversationId: 'c1').toList();
    expect(events.whereType<MessageError>(), hasLength(1));
    expect(events.whereType<ArtifactCreated>(), isEmpty);
  });
}
