import '../../providers/access.dart';
import '../../providers/clients/gemini_image.dart';
import '../../providers/select.dart';
import '../capability.dart';
import '../job_graph.dart';
import '../job_output.dart';
import '../job_runner.dart';
import '../turn_event.dart';

/// Runs an image step.
///
/// Same shape as [TextExecutor] on purpose: selection and credentials resolved
/// here, the runner left knowing nothing about providers. The two together are
/// what make a two-model turn ordinary rather than a special case — this one
/// resolves to the image leader, that one to the text leader, and neither is
/// aware the other exists.
class ImageExecutor implements StepExecutor {
  final bool Function(String providerId) usable;
  final Future<ProviderAccess?> Function(String providerId) access;
  final String? pinned;
  final GeminiImage gemini;

  ImageExecutor({
    required this.usable,
    required this.access,
    this.pinned,
    GeminiImage? gemini,
  }) : gemini = gemini ?? GeminiImage();

  ProviderChoice? get _choice =>
      chooseProvider(Capability.image, usable: usable, pinned: pinned);

  @override
  ({String provider, String model}) identify(JobStep step) {
    final choice = _choice;
    return (
      provider: choice?.provider.displayName ?? 'unavailable',
      model: choice?.model.id ?? '',
    );
  }

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    final choice = _choice;
    if (choice == null) {
      yield StepFailed(
        step.id,
        reason: 'No provider is set up for images yet. Add a key in '
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

    yield* switch (choice.provider.id) {
      'gemini' => gemini.generate(
          stepId: step.id,
          access: credential,
          prompt: step.instruction,
        ),
      // OpenAI images land with the rest of that client. A provider that was
      // selected and cannot be dispatched says so, rather than failing further
      // down where it would read as the provider's fault.
      _ => Stream.value(
          StepFailed(
            step.id,
            reason: '${choice.provider.displayName} images are not wired up '
                'yet.',
          ),
        ),
    };
  }
}
