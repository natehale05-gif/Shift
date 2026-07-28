import 'package:uuid/uuid.dart';

import '../data/models/artifact.dart';
import '../data/models/citation.dart';
import 'chat_service.dart';

const _uuid = Uuid();

/// One search round's harvest.
class ResearchRoundResult {
  final String notes;
  final List<Citation> citations;

  const ResearchRoundResult({required this.notes, required this.citations});
}

/// Provider-agnostic deep-research loop: plan queries → search rounds →
/// synthesize a cited markdown report (delivered as an artifact). The
/// three model-touching steps are injected functions, so the state machine
/// is fully unit-testable and runs on whichever provider the user has a
/// key for.
class DeepResearchEngine {
  final Future<List<String>> Function(String topic) planQueries;
  final Future<ResearchRoundResult> Function(String query) search;
  final Future<String> Function(String topic, String notes) synthesize;
  final int maxRounds;

  bool _cancelled = false;

  DeepResearchEngine({
    required this.planQueries,
    required this.search,
    required this.synthesize,
    this.maxRounds = 6,
  });

  /// Cancels between rounds — the current round finishes, later ones don't
  /// start, and whatever was gathered still gets synthesized.
  void cancel() => _cancelled = true;

  Stream<ChatEvent> run({
    required String topic,
    required String conversationId,
  }) async* {
    yield const DeepResearchProgress(stage: 'planning');

    List<String> queries;
    try {
      queries = (await planQueries(topic)).take(maxRounds).toList();
    } catch (e) {
      yield MessageError('Research planning failed: $e');
      return;
    }
    if (queries.isEmpty) queries = [topic];

    final notes = StringBuffer();
    final citations = <String, Citation>{};
    var completedRounds = 0;

    for (var round = 1; round <= queries.length; round++) {
      if (_cancelled) break;
      final query = queries[round - 1];
      yield DeepResearchProgress(
        stage: 'searching',
        round: round,
        query: query,
        sourceCount: citations.length,
      );
      try {
        final result = await search(query);
        notes.writeln('## Round $round: $query\n${result.notes}\n');
        for (final citation in result.citations) {
          citations[citation.url] = citation;
        }
        completedRounds++;
      } catch (_) {
        // One bad round doesn't sink the run — move to the next query.
        notes.writeln('## Round $round: $query\n(search failed)\n');
      }
    }

    if (completedRounds == 0) {
      yield const MessageError(
          'Deep research could not complete any search rounds.');
      return;
    }

    yield const DeepResearchProgress(stage: 'synthesizing');

    String report;
    try {
      report = await synthesize(topic, notes.toString());
    } catch (e) {
      yield MessageError('Report synthesis failed: $e');
      return;
    }

    final orderedCitations = citations.values.toList();
    yield ArtifactCreated(Artifact(
      id: _uuid.v4(),
      conversationId: conversationId,
      title: 'Research: $topic',
      kind: ArtifactKind.markdown,
      versions: [
        ArtifactVersion(
          content: appendSourcesSection(report, orderedCitations),
          createdAt: DateTime.now(),
        ),
      ],
    ));
    yield MessageDelta(
      _cancelled
          ? 'Stopped early as asked — the report covers the '
              '$completedRounds round${completedRounds == 1 ? '' : 's'} '
              'finished so far.'
          : 'Research complete: $completedRounds round'
              '${completedRounds == 1 ? '' : 's'}, '
              '${orderedCitations.length} sources. The full report is in '
              'the artifact above.',
    );
    if (orderedCitations.isNotEmpty) {
      yield CitationsReady(orderedCitations);
    }
  }

  /// Appends a numbered sources section matching the citation chips.
  static String appendSourcesSection(
    String report,
    List<Citation> citations,
  ) {
    if (citations.isEmpty) return report;
    final buffer = StringBuffer(report.trimRight())..write('\n\n## Sources\n');
    for (var i = 0; i < citations.length; i++) {
      buffer.write('\n${i + 1}. [${citations[i].title}](${citations[i].url})');
    }
    return buffer.toString();
  }
}
