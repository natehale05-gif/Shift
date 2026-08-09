import '../../providers/access.dart';
import '../../providers/clients/anthropic_text.dart';
import '../../providers/select.dart';
import '../capability.dart';
import '../job_graph.dart';
import '../job_output.dart';
import '../job_runner.dart';
import '../turn_event.dart';

/// Runs a text step against whichever provider the account can actually use.
///
/// Everything about *who* and *how it is paid for* is resolved here, so the
/// runner's scheduling — the part with the interesting bugs — stays free of
/// providers, keys and HTTP.
class TextExecutor implements StepExecutor {
  /// Whether this account can use a provider at all: a key, a plan, or both.
  /// Synchronous, because selection has to answer before anything is fetched.
  final bool Function(String providerId) usable;

  /// The credential for a call, resolved per call because a managed session
  /// token is short-lived and must not be cached on the client.
  final Future<ProviderAccess?> Function(String providerId) access;

  final String? pinned;
  final AnthropicText anthropic;

  TextExecutor({
    required this.usable,
    required this.access,
    this.pinned,
    AnthropicText? anthropic,
  }) : anthropic = anthropic ?? AnthropicText();

  ProviderChoice? _choose(JobStep step) =>
      chooseProvider(Capability.text, usable: usable, pinned: pinned);

  @override
  ({String provider, String model}) identify(JobStep step) {
    final choice = _choose(step);
    // Named before the work starts so the UI can say who is doing it while it
    // happens. In a multi-step turn the answer differs per step, which is the
    // whole point — one "model used" label on the turn would be a lie in
    // exactly the case this app is built for.
    return (
      provider: choice?.provider.displayName ?? 'unavailable',
      model: choice?.model.id ?? '',
    );
  }

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    final choice = _choose(step);
    if (choice == null) {
      yield StepFailed(
        step.id,
        reason: 'No provider is set up for writing yet. Add a key in '
            'Settings, or start a plan.',
      );
      return;
    }

    final credential = await access(choice.provider.id);
    if (credential == null) {
      yield StepFailed(
        step.id,
        reason: '${choice.provider.displayName} is not set up. Add a key in '
            'Settings, or start a plan that covers it.',
      );
      return;
    }

    // Upstream outputs become context rather than being ignored. This is what
    // makes the two-provider turn actually collaborative: without it the page
    // step would run *after* the image and know nothing about it, which reads
    // identically in a log and is not the feature.
    final context = _describe(inputs);

    yield* switch (choice.provider.id) {
      'anthropic' => anthropic.stream(
          stepId: step.id,
          access: credential,
          model: choice.model.id,
          instruction: step.instruction,
          system: context,
        ),
      // Gemini and the OpenAI-compatible providers land next; until then a
      // provider that was selected and cannot be dispatched says so plainly
      // rather than failing somewhere further down as a provider error.
      _ => Stream.value(
          StepFailed(
            step.id,
            reason: '${choice.provider.displayName} is not wired up yet.',
          ),
        ),
    };
  }

  /// What the step should know about what came before it.
  ///
  /// Deliberately a description, not the bytes: an image reaches a text model
  /// as "there is a picture, here is what it shows", because the page being
  /// written needs to *refer* to it, not look at it.
  static String? _describe(Map<String, JobOutput> inputs) {
    if (inputs.isEmpty) return null;

    final lines = <String>[];
    for (final entry in inputs.entries) {
      switch (entry.value) {
        case ImageOutput(:final prompt):
          lines.add('An image has already been generated and will be placed '
              'in the result. It shows: $prompt');
        case TextOutput(:final text):
          lines.add('Earlier step "${entry.key}" produced:\n$text');
        case SearchOutput(:final results):
          lines.add('Sources found:\n${results.map((r) => '- ${r.title} '
              '(${r.url})').join('\n')}');
        case final other:
          lines.add('Earlier step "${entry.key}" produced '
              '${other.runtimeType}.');
      }
    }
    return lines.join('\n\n');
  }
}
