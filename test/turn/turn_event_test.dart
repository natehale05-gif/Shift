import 'package:flutter_test/flutter_test.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/turn_event.dart';

/// A switch that must stay exhaustive.
///
/// The compiler already enforces this — that is what sealing buys — but
/// writing it out once means a new event type produces a failure *here*, next
/// to a description of what each case is for, rather than only in whichever
/// widget happened to switch first.
String describe(TurnEvent event) => switch (event) {
      StepStarted(:final label, :final model) => 'start $label on $model',
      StepProgress(:final fraction) => 'progress ${fraction ?? "unknown"}',
      TextDelta(:final text) => 'text $text',
      ThinkingDelta() => 'thinking',
      ToolUseStarted(:final tool) => 'tool $tool',
      ToolUseFinished(:final tool) => 'tool done $tool',
      CitationsFound(:final citations) => 'cite ${citations.length}',
      ArtifactProduced(:final artifact) => 'artifact ${artifact.title}',
      StepCompleted() => 'done',
      StepFailed(:final reason) => 'failed $reason',
      TurnFinished(:final incomplete) => 'finished incomplete=$incomplete',
    };

void main() {
  group('the event vocabulary', () {
    test('every event says which step it belongs to', () {
      // A graph can have several steps in flight at once, so an event that
      // did not name its step could not be placed. Turn-level events use the
      // empty string, which is the one id no step can have.
      const events = <TurnEvent>[
        StepStarted('a', label: 'Drawing', provider: 'openai', model: 'x'),
        TextDelta('a', 'hello'),
        StepFailed('a', reason: 'nope'),
      ];
      for (final e in events) {
        expect(e.stepId, 'a');
      }
      expect(const TurnFinished().stepId, isEmpty);
    });

    test('the model is reported per step, not per turn', () {
      // In a multi-step turn the honest answer to "which model made this" is
      // different for each step — that is the entire point of the graph — so a
      // single label on the turn would be a lie in exactly the case the app
      // exists for.
      const drawing =
          StepStarted('img', label: 'Drawing', provider: 'openai', model: 'a');
      const writing =
          StepStarted('page', label: 'Building', provider: 'anthropic', model: 'b');

      expect(drawing.provider, isNot(writing.provider));
      expect(describe(drawing), contains('a'));
      expect(describe(writing), contains('b'));
    });
  });

  group('failure is partial by design', () {
    test('a step can fail without blocking what depends on it', () {
      // If the picture fails, the page should still be written and should say
      // the picture is missing. v1 collapsed the whole turn, so one flaky
      // provider lost work that had already been paid for.
      const soft = StepFailed('img',
          reason: 'the image provider timed out', blocksDependents: false);
      expect(soft.blocksDependents, isFalse);
    });

    test('but blocking is the default', () {
      // The safe default: a step whose output is genuinely required should
      // not let dependents run on nothing unless someone said so.
      const hard = StepFailed('search', reason: 'no sources');
      expect(hard.blocksDependents, isTrue);
    });

    test('a finished turn can admit it is incomplete', () {
      expect(const TurnFinished().incomplete, isFalse);
      expect(
        const TurnFinished(incomplete: true, note: 'the image failed')
            .incomplete,
        isTrue,
      );
    });
  });

  group('citations carry spans when the provider gives them', () {
    test('a span makes an inline marker possible', () {
      final cited = Citation(
        title: 'Docs',
        url: Uri.parse('https://example.com'),
        start: 10,
        end: 42,
      );
      expect(cited.hasSpan, isTrue);
    });

    test('no offsets degrades to a plain source rather than a guess', () {
      // Placing a marker at an invented position would attach a claim to a
      // sentence that does not make it, which is worse than showing the source
      // without a position.
      final bare =
          Citation(title: 'Docs', url: Uri.parse('https://example.com'));
      expect(bare.hasSpan, isFalse);
    });
  });

  group('exhaustiveness', () {
    test('every event type is handled', () {
      final all = <TurnEvent>[
        const StepStarted('a', label: 'l', provider: 'p', model: 'm'),
        const StepProgress('a'),
        const TextDelta('a', 't'),
        const ThinkingDelta('a', 't'),
        const ToolUseStarted('a', 'search'),
        const ToolUseFinished('a', 'search'),
        const CitationsFound('a', []),
        const StepCompleted('a', TextOutput('x')),
        const StepFailed('a', reason: 'r'),
        const TurnFinished(),
      ];
      for (final event in all) {
        expect(() => describe(event), returnsNormally,
            reason: event.runtimeType.toString());
      }
    });
  });
}
