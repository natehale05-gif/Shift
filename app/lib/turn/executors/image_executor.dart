import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../providers/access.dart';
import '../../providers/clients/gemini_image.dart';
import '../../providers/clients/openai_image.dart';
import '../../providers/failure_text.dart';
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
  final OpenAiImage openai;

  /// Whether this is running in a browser. Same reason as [TextExecutor]'s: a
  /// branch gated on `kIsWeb` is one no test here can enter.
  final bool onWeb;

  /// Resolves a stored picture the step is editing.
  ///
  /// A function rather than the store, so this stays testable with no disk and
  /// so `turn/` keeps not importing `data/`. Null when there is nothing behind
  /// the id, which is a real state — the picture may have been deleted between
  /// choosing it and sending.
  ///
  /// The type comes back with the bytes because a picture the person brought
  /// is often a JPEG, and telling a provider a JPEG is a PNG gets a valid
  /// picture rejected for a reason nobody can see.
  final Future<({Uint8List bytes, String mimeType})?> Function(String imageId)?
      sourceBytes;

  ImageExecutor({
    required this.usable,
    required this.access,
    this.pinned,
    this.sourceBytes,
    GeminiImage? gemini,
    OpenAiImage? openai,
    this.onWeb = kIsWeb,
  })  : gemini = gemini ?? GeminiImage(),
        openai = openai ?? OpenAiImage();

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

    // Resolved here rather than carried on the plan, so a plan stays a small
    // comparable value. Refused rather than quietly generated: someone who
    // asked to change *this* picture and got a new unrelated one has been
    // charged for the wrong thing and has to notice it themselves.
    ({Uint8List bytes, String mimeType})? source;
    if (step.editing case final id?) {
      source = await sourceBytes?.call(id);
      if (source == null) {
        yield StepFailed(
          step.id,
          reason: 'That picture is no longer on this device, so there is '
              'nothing to change. Describing it again will make a new one.',
        );
        return;
      }
    }

    final base = choice.provider.baseUrl;
    final blocked =
        sentenceForBrowserBlocked(choice.provider, onWeb: onWeb);

    yield* switch (choice.provider.id) {
      'gemini' => gemini.generate(
          stepId: step.id,
          access: credential,
          prompt: step.instruction,
          source: source?.bytes,
          sourceMimeType: source?.mimeType ?? 'image/png',
          aspectRatio: step.aspectRatio,
        ),

      // OpenAI's endpoint makes a picture and cannot change one. Refused
      // rather than quietly generating a new unrelated image: somebody who
      // asked to change *this* picture and got a different one has been
      // charged for the wrong thing and has to notice it themselves.
      'openai' when source != null => Stream.value(
          StepFailed(
            step.id,
            reason: 'OpenAI can make a new picture but not change an existing '
                'one. Add a Gemini key to edit pictures, or describe the '
                'whole picture you want.',
          ),
        ),
      'openai' when base != null => openai.generate(
          stepId: step.id,
          access: credential,
          model: choice.model.id,
          baseUrl: base,
          prompt: step.instruction,
          aspectRatio: step.aspectRatio,
          blocked: blocked,
        ),

      // A provider selected for images with no client behind it. Says so,
      // rather than failing further down where it would read as the
      // provider's fault.
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
