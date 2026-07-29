

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
library;
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../code/code_request_sheet.dart';
import '../copy/copy_scripts_request_sheet.dart';
import '../image/image_request_sheet.dart';
import '../shared/chip_selector.dart';
import '../shared/sheet_scaffold.dart';
import '../video/video_request_sheet.dart';
import 'music_request_sheet.dart';
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


class VoiceAvatarRequestSheet extends StatefulWidget {
  const VoiceAvatarRequestSheet({super.key});

  @override
  State<VoiceAvatarRequestSheet> createState() => _VoiceAvatarRequestSheetState();
}


class _VoiceAvatarRequestSheetState extends State<VoiceAvatarRequestSheet> {
  final _scriptController = TextEditingController();
  String _voice = 'Aria';
  String _tone = 'Friendly';
  String _platform = 'Web';

  static const _voices = ['Aria', 'Jasper', 'Nova'];
  static const _tones = ['Friendly', 'Professional', 'Energetic'];
  static const _platforms = ['Web', 'YouTube', 'TikTok', 'Podcast'];

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.voiceAvatarStudio,
      canSubmit: _scriptController.text.trim().isNotEmpty,
      onSubmit: () => Navigator.of(context).pop(
        VoiceAvatarRequest(
          script: _scriptController.text.trim(),
          voice: _voice,
          tone: _tone,
          platform: _platform,
        ),
      ),
      fields: [
        TextField(
          controller: _scriptController,
          decoration: const InputDecoration(hintText: 'Script to narrate…'),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        ChipSelector(
          label: 'Voice',
          options: _voices,
          selected: _voice,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _voice = v),
        ),
        ChipSelector(
          label: 'Tone',
          options: _tones,
          selected: _tone,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _tone = v),
        ),
        ChipSelector(
          label: 'Platform',
          options: _platforms,
          selected: _platform,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _platform = v),
        ),
      ],
    );
  }
}
