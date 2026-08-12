import 'package:flutter/foundation.dart' show kIsWeb;

import '../../providers/access.dart';
import '../../providers/failure_text.dart';
import '../../providers/clients/anthropic_text.dart';
import '../../providers/clients/gemini_text.dart';
import '../../providers/clients/openai_text.dart';
import '../../providers/select.dart';
import '../capability.dart';
import '../extract_artifact.dart';
import '../fence_filter.dart';
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

  /// Why there is nothing to run this with, when [usable] finds nothing.
  ///
  /// Injected rather than written here because the answer depends on the
  /// account — no plan, a spent one, one that does not cover this, or one that
  /// could not be read — and `turn/` deliberately knows nothing about accounts.
  /// The default is the signed-out sentence, which is the honest answer when
  /// nobody supplied a better one.
  final String Function(String what) explainUnavailable;

  final String? pinned;
  final AnthropicText anthropic;
  final GeminiText gemini;
  final OpenAiText openai;

  /// Which conversation an artifact belongs to, read at the moment one is
  /// produced rather than held — the id is minted on the first message, so a
  /// value captured when the executors were built would be the previous
  /// conversation's, or nothing at all.
  final String Function() conversationId;

  /// Whether this is running in a browser, which is the only place a provider's
  /// CORS policy can refuse a call. A field rather than a read of `kIsWeb`
  /// because every test in this app runs off-web, so the branch that matters
  /// would be one no test could enter.
  final bool onWeb;

  TextExecutor({
    required this.usable,
    required this.access,
    this.explainUnavailable = defaultUnavailable,
    this.pinned,
    AnthropicText? anthropic,
    GeminiText? gemini,
    OpenAiText? openai,
    String Function()? conversationId,
    this.onWeb = kIsWeb,
  })  : anthropic = anthropic ?? AnthropicText(),
        gemini = gemini ?? GeminiText(),
        openai = openai ?? OpenAiText(),
        conversationId = conversationId ?? _noConversation;

  static String _noConversation() => '';

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
        reason: explainUnavailable('writing'),
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
    // The brief first, then what upstream steps produced. Order matters for
    // a long system prompt: standing instructions read as rules when they
    // come before the material and as suggestions when they come after it.
    final parts = [step.brief, _describe(inputs)]
        .whereType<String>()
        .where((part) => part.isNotEmpty);
    final context = parts.isEmpty ? null : parts.join('\n\n');

    // Dispatch on the *wire*, not on the provider: four of these speak the
    // same protocol and differ only in a base URL, so there is one client for
    // them rather than four near-identical files where a fix gets applied
    // three times.
    //
    // The fallthrough is a `baseUrl` missing from the registry, which is a
    // programming error rather than a state a user can reach — so it says that
    // rather than blaming the provider.
    // Composed here because this is the only layer that knows *which* provider
    // was chosen: one of the three clients below serves four of them. On the
    // web a provider that allows no calls from a page fails exactly like a
    // content blocker, and the generic advice — try another browser — is then
    // an instruction to keep doing the thing that cannot work.
    final base = choice.provider.baseUrl;
    final blocked =
        sentenceForBrowserBlocked(choice.provider, onWeb: onWeb);
    final events = switch (choice.provider.id) {
      'anthropic' => anthropic.stream(
          stepId: step.id,
          access: credential,
          model: choice.model.id,
          instruction: step.instruction,
          system: context,
          blocked: blocked,
          history: step.history,
        ),
      'gemini' => gemini.stream(
          stepId: step.id,
          access: credential,
          model: choice.model.id,
          instruction: step.instruction,
          system: context,
          blocked: blocked,
          history: step.history,
        ),
      _ when base != null => openai.stream(
          stepId: step.id,
          access: credential,
          model: choice.model.id,
          baseUrl: base,
          instruction: step.instruction,
          system: context,
          blocked: blocked,
          history: step.history,
        ),
      _ => Stream.value(
          StepFailed(
            step.id,
            reason: '${choice.provider.displayName} has no endpoint '
                'configured.',
          ),
        ),
    };

    yield* _withArtifact(step, events);
  }

  /// Holds fenced blocks back from the transcript, and at the end either turns
  /// them into an artifact or puts them back.
  ///
  /// **Here rather than in the client**, so one implementation covers every
  /// provider. v1 shipped this inside its Anthropic path and the consequence
  /// was that Gemini and OpenAI produced no artifacts at all — a fence in the
  /// chat and an empty panel — for months.
  ///
  /// The invariant, stated once: **withholding is a presentation choice, so
  /// every exit path either turns held text into an artifact or puts it back in
  /// the reply.** v1 lost whole pages to a version of this that only handled a
  /// clean finish.
  Stream<TurnEvent> _withArtifact(
    JobStep step,
    Stream<TurnEvent> events,
  ) async* {
    final fences = FenceFilter();
    final reply = StringBuffer();
    var failed = false;
    var ended = false;

    Stream<TurnEvent> finish() async* {
      if (ended) return;
      ended = true;

      final trailing = fences.flush();
      if (trailing.isNotEmpty) yield TextDelta(step.id, trailing);
      if (!fences.sawFence) return;

      // Extraction only on a clean finish: half a document previews as a
      // broken page, and presenting one as a deliverable is worse than showing
      // the source. The held text still comes back either way.
      final artifact = failed
          ? null
          : extractArtifact(
              reply.toString(),
              conversationId: conversationId(),
              request: step.instruction,
            );

      if (artifact != null) {
        yield ArtifactProduced(step.id, artifact);
      } else {
        yield TextDelta(step.id, fences.replayText());
      }
    }

    await for (final event in events) {
      switch (event) {
        case TextDelta(:final text):
          reply.write(text);
          final prose = fences.feed(text);
          if (prose.isNotEmpty) yield TextDelta(step.id, prose);

        // All three endings are terminal. A `StepFailed` mid-fence is the
        // truncated-reply case — the model hit its ceiling — and it is exactly
        // where v1 dropped the page on the floor.
        case StepFailed():
          failed = true;
          yield* finish();
          yield event;

        case StepCompleted():
          yield* finish();
          yield event;

        default:
          yield event;
      }
    }

    yield* finish();
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
