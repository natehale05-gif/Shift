import 'package:flutter/material.dart';

/// The specialized AI "studio" a request is routed to by the middleware AI.
enum StudioType {
  middleware,
  imageStudio,
  videoStudio,
  voiceAvatarStudio,
  musicStudio,
  copyScriptsStudio;

  String get displayName => switch (this) {
        StudioType.middleware => 'SHIFT AI',
        StudioType.imageStudio => 'Image Studio',
        StudioType.videoStudio => 'Video Studio',
        StudioType.voiceAvatarStudio => 'Voice & Avatar Studio',
        StudioType.musicStudio => 'Music Studio',
        StudioType.copyScriptsStudio => 'Copy & Scripts Studio',
      };

  String get shortName => switch (this) {
        StudioType.middleware => 'Middleware',
        StudioType.imageStudio => 'Image',
        StudioType.videoStudio => 'Video',
        StudioType.voiceAvatarStudio => 'Voice & Avatar',
        StudioType.musicStudio => 'Music',
        StudioType.copyScriptsStudio => 'Copy & Scripts',
      };

  String get tagline => switch (this) {
        StudioType.middleware => 'Your one AI that talks to all the others.',
        StudioType.imageStudio => 'Pixel-perfect, on-brand, in seconds.',
        StudioType.videoStudio => 'From a script to a hero asset.',
        StudioType.voiceAvatarStudio =>
          'Your voice, your face, any language.',
        StudioType.musicStudio => 'Drop a vibe, get a track.',
        StudioType.copyScriptsStudio => 'Hooks, captions, scripts, sold.',
      };

  IconData get icon => switch (this) {
        StudioType.middleware => Icons.auto_awesome_rounded,
        StudioType.imageStudio => Icons.image_rounded,
        StudioType.videoStudio => Icons.movie_creation_rounded,
        StudioType.voiceAvatarStudio => Icons.record_voice_over_rounded,
        StudioType.musicStudio => Icons.music_note_rounded,
        StudioType.copyScriptsStudio => Icons.edit_note_rounded,
      };

  Color get accent => switch (this) {
        StudioType.middleware => const Color(0xFF6C6CE5),
        StudioType.imageStudio => const Color(0xFFE5787A),
        StudioType.videoStudio => const Color(0xFF4FB0E8),
        StudioType.voiceAvatarStudio => const Color(0xFF56C596),
        StudioType.musicStudio => const Color(0xFFE6A23C),
        StudioType.copyScriptsStudio => const Color(0xFFB07CE0),
      };

  static StudioType fromName(String name) => StudioType.values.firstWhere(
        (e) => e.name == name,
        orElse: () => StudioType.middleware,
      );
}
