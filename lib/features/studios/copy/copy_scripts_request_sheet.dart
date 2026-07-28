

import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../audio/music_request_sheet.dart';
import '../audio/voice_avatar_request_sheet.dart';
import '../code/code_request_sheet.dart';
import '../image/image_request_sheet.dart';
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


class CopyScriptsRequestSheet extends StatefulWidget {
  const CopyScriptsRequestSheet();

  @override
  State<CopyScriptsRequestSheet> createState() => _CopyScriptsRequestSheetState();
}


class _CopyScriptsRequestSheetState extends State<CopyScriptsRequestSheet> {
  final _notesController = TextEditingController();
  String _contentType = 'Hook';
  String _tone = 'Bold';
  String _platform = 'Instagram';

  static const _contentTypes = ['Hook', 'Caption', 'Script', 'Sales Letter', 'Ad Copy'];
  static const _tones = ['Playful', 'Bold', 'Luxury', 'Direct-response'];
  static const _platforms = ['Instagram', 'TikTok', 'Email', 'Web', 'YouTube'];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.copyScriptsStudio,
      canSubmit: true,
      onSubmit: () => Navigator.of(context).pop(
        CopyScriptsRequest(
          contentType: _contentType,
          tone: _tone,
          platform: _platform,
          brandNotes: _notesController.text.trim(),
        ),
      ),
      fields: [
        ChipSelector(
          label: 'Content type',
          options: _contentTypes,
          selected: _contentType,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _contentType = v),
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
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(hintText: 'Brand voice notes (optional)…'),
          maxLines: 2,
        ),
      ],
    );
  }
}
