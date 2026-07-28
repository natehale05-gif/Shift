

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
library;
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../audio/music_request_sheet.dart';
import '../audio/voice_avatar_request_sheet.dart';
import '../code/code_request_sheet.dart';
import '../copy/copy_scripts_request_sheet.dart';
import '../image/image_request_sheet.dart';
import '../video/video_request_sheet.dart';
import 'package:flutter/material.dart';

Future<StudioRequest?> showStudioRequestSheet(
  BuildContext context,
  StudioType studioType,
) {
  return showModalBottomSheet<StudioRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => switch (studioType) {
      StudioType.imageStudio => const ImageRequestSheet(),
      StudioType.videoStudio => const VideoRequestSheet(),
      StudioType.voiceAvatarStudio ||
      StudioType.voiceStudio ||
      StudioType.avatarStudio =>
        const VoiceAvatarRequestSheet(),
      StudioType.musicStudio => const MusicRequestSheet(),
      StudioType.copyScriptsStudio => const CopyScriptsRequestSheet(),
      StudioType.codeStudio => const CodeRequestSheet(),
      // Translate/Deck/ShortReels/Brand Pack are driven from chat (no
      // structured form), so no sheet.
      _ => throw ArgumentError('No sheet for $studioType'),
    },
  );
}


class ChipSelector<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T selected;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;

  const ChipSelector({super.key, 
    required this.label,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(labelBuilder(option)),
                selected: option == selected,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
