

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
library;
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/studio_style.dart';
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


class SheetScaffold extends StatelessWidget {
  final StudioType studioType;
  final List<Widget> fields;
  final VoidCallback onSubmit;
  final bool canSubmit;

  const SheetScaffold({super.key, 
    required this.studioType,
    required this.fields,
    required this.onSubmit,
    required this.canSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(studioType.icon, color: studioType.accent),
                const SizedBox(width: AppSpacing.sm),
                Text(studioType.displayName, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(studioType.tagline, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            ...fields,
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: canSubmit ? onSubmit : null,
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }
}
