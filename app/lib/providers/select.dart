import '../turn/capability.dart';
import 'registry.dart';

/// The provider and model chosen for one step.
class ProviderChoice {
  final ProviderDescriptor provider;
  final ProviderModel model;

  const ProviderChoice(this.provider, this.model);
}

/// Picks who does a step. Pure: it reads the table and the caller's answer to
/// "can this account use that provider", and nothing else.
///
/// **Per step, not per turn.** That is the entire mechanism behind "different
/// models working together on one request": the image step resolves to
/// whichever image provider is available, the writing step to whichever text
/// provider is, and neither knows the other exists. In v1 this was a table of
/// eight named combinations; here it falls out of asking the question once per
/// step.
///
/// Returns null when nothing available can do it — a real state, and the
/// caller's job to turn into a sentence. It deliberately does **not** fall
/// back to some default provider: a step answered by a model that cannot do
/// the job fails later, further away, and with a worse message.
ProviderChoice? chooseProvider(
  Capability capability, {
  required bool Function(String providerId) usable,
  String? pinned,
}) {
  // A pin is a statement about the provider, and it is honoured even when the
  // ranking disagrees — that is what pinning is for. It is not honoured when
  // the pinned provider cannot do the job at all, because silently ignoring
  // the request would be worse than the pin being irrelevant to this step.
  if (pinned != null) {
    final provider = providerById(pinned);
    final model = provider?.modelFor(capability);
    if (provider != null && model != null && usable(provider.id)) {
      return ProviderChoice(provider, model);
    }
  }

  ProviderChoice? best;
  int? bestRank;

  for (final provider in kProviders) {
    final rank = provider.ranks[capability];
    if (rank == null) continue;
    if (!usable(provider.id)) continue;

    final model = provider.modelFor(capability);
    if (model == null) continue;

    if (bestRank == null || rank < bestRank) {
      bestRank = rank;
      best = ProviderChoice(provider, model);
    }
  }

  return best;
}
