

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../audio/music_request_sheet.dart';
import '../audio/voice_avatar_request_sheet.dart';
import '../code/code_request_sheet.dart';
import '../copy/copy_scripts_request_sheet.dart';
import '../shared/chip_selector.dart';
import '../shared/sheet_scaffold.dart';
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


class ImageRequestSheet extends StatefulWidget {
  const ImageRequestSheet();

  @override
  State<ImageRequestSheet> createState() => _ImageRequestSheetState();
}


class _ImageRequestSheetState extends State<ImageRequestSheet> {
  final _promptController = TextEditingController();
  String _aspectRatio = '1:1';
  String _style = 'Product Shot';
  int _count = 1;

  static const _aspectRatios = ['1:1', '4:5', '16:9', '9:16'];
  static const _styles = ['Product Shot', 'Lifestyle', 'Ad Creative', 'Abstract'];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.imageStudio,
      canSubmit: _promptController.text.trim().isNotEmpty,
      onSubmit: () => Navigator.of(context).pop(
        ImageRequest(
          prompt: _promptController.text.trim(),
          aspectRatio: _aspectRatio,
          stylePreset: _style,
          count: _count,
        ),
      ),
      fields: [
        TextField(
          controller: _promptController,
          decoration: const InputDecoration(hintText: 'Describe the image…'),
          maxLines: 2,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        ChipSelector(
          label: 'Aspect ratio',
          options: _aspectRatios,
          selected: _aspectRatio,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _aspectRatio = v),
        ),
        ChipSelector(
          label: 'Style',
          options: _styles,
          selected: _style,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _style = v),
        ),
        ChipSelector(
          label: 'Count',
          options: const [1, 2, 4],
          selected: _count,
          labelBuilder: (v) => '$v',
          onSelected: (v) => setState(() => _count = v),
        ),
      ],
    );
  }
}
