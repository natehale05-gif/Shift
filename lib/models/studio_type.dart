import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The specialized AI "studio" a request is routed to by the middleware AI.
enum StudioType {
  middleware,
  imageStudio,
  videoStudio,
  voiceAvatarStudio,
  musicStudio,
  copyScriptsStudio,
  codeStudio;

  String get displayName => switch (this) {
        StudioType.middleware => 'SHIFT AI',
        StudioType.imageStudio => 'Image Studio',
        StudioType.videoStudio => 'Video Studio',
        StudioType.voiceAvatarStudio => 'Voice & Avatar Studio',
        StudioType.musicStudio => 'Music Studio',
        StudioType.copyScriptsStudio => 'Copy & Scripts Studio',
        StudioType.codeStudio => 'Code Studio',
      };

  String get shortName => switch (this) {
        StudioType.middleware => 'Middleware',
        StudioType.imageStudio => 'Image',
        StudioType.videoStudio => 'Video',
        StudioType.voiceAvatarStudio => 'Voice & Avatar',
        StudioType.musicStudio => 'Music',
        StudioType.copyScriptsStudio => 'Copy & Scripts',
        StudioType.codeStudio => 'Code',
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
      };

  IconData get icon => switch (this) {
        StudioType.middleware => Icons.auto_awesome_rounded,
        StudioType.imageStudio => Icons.image_rounded,
        StudioType.videoStudio => Icons.movie_creation_rounded,
        StudioType.voiceAvatarStudio => Icons.record_voice_over_rounded,
        StudioType.musicStudio => Icons.music_note_rounded,
        StudioType.copyScriptsStudio => Icons.edit_note_rounded,
        StudioType.codeStudio => Icons.code_rounded,
      };

  /// Each studio's accent is one of Apple's own named system colors, so the
  /// per-studio badges/chips read as part of the same system as the rest of
  /// the chrome rather than an arbitrary brand palette.
  Color get accent => switch (this) {
        StudioType.middleware => AppColors.accent, // systemIndigo
        StudioType.imageStudio => AppColors.systemPink,
        StudioType.videoStudio => AppColors.systemBlue,
        StudioType.voiceAvatarStudio => AppColors.systemGreen,
        StudioType.musicStudio => AppColors.systemOrange,
        StudioType.copyScriptsStudio => AppColors.systemPurple,
        StudioType.codeStudio => AppColors.systemTeal,
      };

  static StudioType fromName(String name) => StudioType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => StudioType.middleware,
      );
}
