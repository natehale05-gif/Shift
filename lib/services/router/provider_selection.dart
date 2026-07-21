import '../providers/provider_capability.dart';
import '../providers/provider_registry.dart';
import 'model_router.dart';

/// The provider capability a routed request needs. This is the bridge between
/// the router's [ChatRoute] vocabulary and the registry's capability-based
/// preference orders (the "Auto" decision).
ProviderCapability capabilityForRoute(ChatRoute route) => switch (route) {
      ChatRoute.chat => ProviderCapability.chat,
      ChatRoute.code => ProviderCapability.code,
      ChatRoute.writing => ProviderCapability.writing,
      ChatRoute.imageGen => ProviderCapability.image,
      ChatRoute.webSearch => ProviderCapability.search,
      ChatRoute.deepResearch => ProviderCapability.search,
      ChatRoute.video => ProviderCapability.video,
      ChatRoute.audio => ProviderCapability.voice,
      // Voiceover uses a voice provider; a talking-head avatar its own.
      ChatRoute.voice => ProviderCapability.voice,
      ChatRoute.avatar => ProviderCapability.avatar,
      // Translate and Deck are text tasks (best text provider writes them).
      ChatRoute.translate => ProviderCapability.writing,
      ChatRoute.deck => ProviderCapability.writing,
      // A short-form pack leans on video; a brand pack on image.
      ChatRoute.shortReels => ProviderCapability.video,
      ChatRoute.brandPack => ProviderCapability.image,
    };

/// The best available provider for [route]: the first provider in the
/// capability's preference order that the user has a key for. Returns null when
/// none is available (the caller then falls back to the mock). Pure — the
/// [hasKey] predicate is injected, so this is exhaustively unit-testable.
String? chooseProvider(
  ChatRoute route, {
  required ProviderRegistry registry,
  required bool Function(String providerId) hasKey,
}) {
  final capability = capabilityForRoute(route);
  for (final descriptor in registry.providersFor(capability)) {
    if (hasKey(descriptor.id)) return descriptor.id;
  }
  return null;
}
