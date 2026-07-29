/// The specialized AI "studio" a request is routed to by the middleware AI.
enum StudioType {
  middleware,
  imageStudio,
  videoStudio,
  voiceAvatarStudio,
  musicStudio,
  copyScriptsStudio,
  codeStudio,
  // The expanded studio set — Voice and Avatar are split out of the combined
  // Voice & Avatar studio (which is retained for internal composition), plus
  // four new deliverable studios.
  voiceStudio,
  avatarStudio,
  translateStudio,
  deckStudio,
  shortReelsStudio,
  brandPackStudio;

  String get displayName => switch (this) {
        StudioType.middleware => 'SHIFT AI',
        StudioType.imageStudio => 'Image Studio',
        StudioType.videoStudio => 'Video Studio',
        StudioType.voiceAvatarStudio => 'Voice & Avatar Studio',
        StudioType.musicStudio => 'Music Studio',
        StudioType.copyScriptsStudio => 'Copy & Scripts Studio',
        StudioType.codeStudio => 'Code Studio',
        StudioType.voiceStudio => 'Voice Studio',
        StudioType.avatarStudio => 'Avatar Studio',
        StudioType.translateStudio => 'Translate Studio',
        StudioType.deckStudio => 'Deck Studio',
        StudioType.shortReelsStudio => 'ShortReels Studio',
        StudioType.brandPackStudio => 'Brand Pack Studio',
      };

  String get shortName => switch (this) {
        StudioType.middleware => 'Chat',
        StudioType.imageStudio => 'Image',
        StudioType.videoStudio => 'Video',
        StudioType.voiceAvatarStudio => 'Voice & Avatar',
        StudioType.musicStudio => 'Music',
        StudioType.copyScriptsStudio => 'Copy & Scripts',
        StudioType.codeStudio => 'Code',
        StudioType.voiceStudio => 'Voice',
        StudioType.avatarStudio => 'Avatar',
        StudioType.translateStudio => 'Translate',
        StudioType.deckStudio => 'Deck',
        StudioType.shortReelsStudio => 'ShortReels',
        StudioType.brandPackStudio => 'Brand Pack',
      };

  String get tagline => switch (this) {
        StudioType.middleware => 'Your one AI that talks to all the others.',
        StudioType.imageStudio => 'Pixel-perfect, on-brand, in seconds.',
        StudioType.videoStudio => 'From a script to a hero asset.',
        StudioType.voiceAvatarStudio =>
          'Your voice, your face, any language.',
        StudioType.musicStudio => 'Drop a vibe, get a track.',
        StudioType.copyScriptsStudio => 'Hooks, captions, scripts, sold.',
        StudioType.codeStudio => 'Ship code, not just chat.',
        StudioType.voiceStudio => 'Studio-grade voiceover, any script.',
        StudioType.avatarStudio => 'A talking-head video of you.',
        StudioType.translateStudio => 'Any document, any language.',
        StudioType.deckStudio => 'Slides and PowerPoint, drafted.',
        StudioType.shortReelsStudio => 'A pack of short-form videos.',
        StudioType.brandPackStudio => 'A full brand kit in one bundle.',
      };



  static StudioType fromName(String name) => StudioType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => StudioType.middleware,
      );
}
