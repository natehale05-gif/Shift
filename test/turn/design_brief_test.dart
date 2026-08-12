import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/streaming/sse_client.dart';
import 'package:shift/turn/executors/text_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/design_brief.dart';
import 'package:shift/turn/plan_jobs.dart';
import 'package:shift/turn/turn_request.dart';

/// What Design mode adds to a turn.
void main() {
  test('a design turn carries the brief', () {
    final graph = planJobs(const TurnRequest(
        input: 'a poster for a jazz night', mode: AppMode.design));

    final step = graph.steps.single;
    expect(step.needs, Capability.text);
    expect(step.brief, kDesignBrief);
  });

  test('no other mode carries it', () {
    // The brief is a long standing instruction. Leaking it into Chat would
    // make every ordinary answer come back as a single HTML file.
    for (final mode in AppMode.values) {
      if (mode == AppMode.design) continue;
      final graph =
          planJobs(TurnRequest(input: 'a poster for a jazz night', mode: mode));
      for (final step in graph.steps) {
        expect(step.brief, isNull, reason: '${mode.name}/${step.id}');
      }
    }
  });

  test('the brief is not part of what was asked', () {
    // It travels in the system prompt, not the request. Folded into the
    // instruction it becomes something the model can answer *about* instead
    // of follow — and the transcript would show the person saying it.
    const request =
        TurnRequest(input: 'a poster for a jazz night', mode: AppMode.design);

    expect(request.prompt, 'a poster for a jazz night');
    expect(planJobs(request).steps.single.instruction, request.prompt);
  });

  test('the brief reaches the model as a system instruction', () async {
    // The plan carrying it proves nothing on its own: the executor merges the
    // brief with upstream outputs, and dropping it there is invisible
    // everywhere except in the request body. Removing that merge left every
    // other test in this file green.
    final sent = _Records();
    final executor = TextExecutor(
      usable: (_) => true,
      access: (_) async => const DirectKey('sk-ant-x'),
      anthropic: AnthropicText(sse: sent),
      conversationId: () => 'c1',
    );

    await executor
        .run(
          const JobStep(
            id: 's',
            label: 'Designing',
            needs: Capability.text,
            produces: OutputKind.text,
            instruction: 'a poster for a jazz night',
            brief: kDesignBrief,
          ),
          const {},
        )
        .toList();

    final body = jsonDecode(sent.body!) as Map<String, dynamic>;
    expect('${body['system']}', contains('self-contained'));
    // And it is *not* in the request: the transcript would otherwise show the
    // person having said all of it.
    expect('${body['messages']}', isNot(contains('self-contained')));
  });

  group('the brief itself', () {
    test('asks for one self-contained file', () {
      // Every external reference is a design that renders as fallbacks on the
      // machine it is opened on.
      expect(kDesignBrief, contains('self-contained'));
      expect(kDesignBrief, contains('Inline all CSS'));
    });

    test('rules out placeholder text', () {
      // Lorem is how a layout hides the fact that nobody decided what it says.
      expect(kDesignBrief.toLowerCase(), contains('lorem'));
    });

    test('asks for both themes', () {
      expect(kDesignBrief, contains('prefers-color-scheme: dark'));
    });

    test('names no colours', () {
      // A brief that specified the palette would make every design the same
      // design, which is the failure mode people recognise instantly as
      // machine-made. It specifies the decisions, not the answers.
      expect(kDesignBrief, isNot(matches(RegExp(r'#[0-9a-fA-F]{6}'))));
    });

    test('asks for the file in one fenced block', () {
      // Extraction pulls a fenced block out of the reply; a design split
      // across three of them arrives as prose with no artifact.
      expect(kDesignBrief, contains('single fenced code block'));
    });
  });
}

/// Captures the request body a client sends.
class _Records implements SseClient {
  String? body;

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    this.body = body;
    return const Stream.empty();
  }
}
