import 'package:flutter/material.dart';

import '../../data/models/project.dart';
import '../../data/models/studio_type.dart';
import 'app_colors.dart';

/// Presentation for the domain enums.
///
/// [StudioType] and [Project] live in `data/` and describe *what* something is;
/// how it looks belongs to the theme. Keeping the colours and icons here is
/// what lets `data/` stay free of `package:flutter/material.dart`, so models
/// can be exercised in plain Dart tests and reasoned about without dragging in
/// the widget layer.
extension StudioStyle on StudioType {
  /// Each studio's accent is one of Apple's own named system colors, so the
  /// per-studio badges/chips read as part of the same system as the rest of
  /// the chrome rather than an arbitrary brand palette.
  Color get accent => switch (this) {
        StudioType.middleware => AppColors.systemIndigo,
        StudioType.imageStudio => AppColors.systemPink,
        StudioType.videoStudio => AppColors.systemBlue,
        StudioType.voiceAvatarStudio => AppColors.systemGreen,
        StudioType.musicStudio => AppColors.systemOrange,
        // systemIndigo, not systemPurple: purple is the app-wide tint now,
        // and the middleware routing chip (indigo's old home) never renders.
        StudioType.copyScriptsStudio => AppColors.systemIndigo,
        StudioType.codeStudio => AppColors.systemTeal,
        StudioType.voiceStudio => AppColors.systemGreen,
        StudioType.avatarStudio => AppColors.systemTeal,
        StudioType.translateStudio => AppColors.systemBlue,
        StudioType.deckStudio => AppColors.systemOrange,
        StudioType.shortReelsStudio => AppColors.systemPink,
        StudioType.brandPackStudio => AppColors.systemPurple,
      };

  IconData get icon => switch (this) {
        StudioType.middleware => Icons.auto_awesome_rounded,
        StudioType.imageStudio => Icons.image_rounded,
        StudioType.videoStudio => Icons.movie_creation_rounded,
        StudioType.voiceAvatarStudio => Icons.record_voice_over_rounded,
        StudioType.musicStudio => Icons.music_note_rounded,
        StudioType.copyScriptsStudio => Icons.edit_note_rounded,
        StudioType.codeStudio => Icons.code_rounded,
        StudioType.voiceStudio => Icons.record_voice_over_rounded,
        StudioType.avatarStudio => Icons.face_retouching_natural_rounded,
        StudioType.translateStudio => Icons.translate_rounded,
        StudioType.deckStudio => Icons.slideshow_rounded,
        StudioType.shortReelsStudio => Icons.movie_filter_rounded,
        StudioType.brandPackStudio => Icons.style_rounded,
      };
}

/// Swatches a project can be tinted with, in [Project.colorIndex] order.
///
/// Must stay [kProjectColorCount] long — that constant is what stores use to
/// assign `colorIndex` round-robin without importing this file.
const List<Color> kProjectColors = [
  AppColors.accent,
  AppColors.systemIndigo,
  AppColors.systemBlue,
  AppColors.systemGreen,
  AppColors.systemOrange,
  AppColors.systemPurple,
];

extension ProjectStyle on Project {
  Color get color => kProjectColors[colorIndex % kProjectColors.length];
}
