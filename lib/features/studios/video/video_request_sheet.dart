

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
import '../shared/chip_selector.dart';
import '../shared/sheet_scaffold.dart';
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


class VideoRequestSheet extends StatefulWidget {
  const VideoRequestSheet({super.key});

  @override
  State<VideoRequestSheet> createState() => _VideoRequestSheetState();
}


class _VideoRequestSheetState extends State<VideoRequestSheet> {
  final _promptController = TextEditingController();
  int _duration = 10;
  String _aspectRatio = '16:9';
  bool _identityLock = false;

  static const _durations = [5, 10, 15, 30];
  static const _aspectRatios = ['16:9', '9:16', '1:1'];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.videoStudio,
      canSubmit: _promptController.text.trim().isNotEmpty,
      onSubmit: () => Navigator.of(context).pop(
        VideoRequest(
          prompt: _promptController.text.trim(),
          durationSec: _duration,
          aspectRatio: _aspectRatio,
          identityLock: _identityLock,
        ),
      ),
      fields: [
        TextField(
          controller: _promptController,
          decoration: const InputDecoration(hintText: 'Describe the shot…'),
          maxLines: 2,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        ChipSelector(
          label: 'Duration',
          options: _durations,
          selected: _duration,
          labelBuilder: (v) => '${v}s',
          onSelected: (v) => setState(() => _duration = v),
        ),
        ChipSelector(
          label: 'Aspect ratio',
          options: _aspectRatios,
          selected: _aspectRatio,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _aspectRatio = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Identity lock'),
          subtitle: const Text('Keep the same subject consistent across shots'),
          value: _identityLock,
          onChanged: (v) => setState(() => _identityLock = v),
        ),
      ],
    );
  }
}
