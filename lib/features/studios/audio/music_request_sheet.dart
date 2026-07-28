

import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../code/code_request_sheet.dart';
import '../copy/copy_scripts_request_sheet.dart';
import '../image/image_request_sheet.dart';
import '../shared/chip_selector.dart';
import '../shared/sheet_scaffold.dart';
import '../video/video_request_sheet.dart';
import 'package:flutter/material.dart';
import 'voice_avatar_request_sheet.dart';

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


class MusicRequestSheet extends StatefulWidget {
  const MusicRequestSheet();

  @override
  State<MusicRequestSheet> createState() => _MusicRequestSheetState();
}


class _MusicRequestSheetState extends State<MusicRequestSheet> {
  String _mood = 'Uplifting';
  int _duration = 30;
  double _bpm = 100;

  static const _moods = ['Uplifting', 'Cinematic', 'Lo-fi', 'Corporate'];
  static const _durations = [15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.musicStudio,
      canSubmit: true,
      onSubmit: () => Navigator.of(context).pop(
        MusicRequest(mood: _mood, durationSec: _duration, bpm: _bpm.round()),
      ),
      fields: [
        ChipSelector(
          label: 'Mood / genre',
          options: _moods,
          selected: _mood,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _mood = v),
        ),
        ChipSelector(
          label: 'Duration',
          options: _durations,
          selected: _duration,
          labelBuilder: (v) => '${v}s',
          onSelected: (v) => setState(() => _duration = v),
        ),
        Text('Tempo · ${_bpm.round()} BPM', style: Theme.of(context).textTheme.labelMedium),
        Slider(
          value: _bpm,
          min: 60,
          max: 160,
          divisions: 20,
          label: '${_bpm.round()} BPM',
          onChanged: (v) => setState(() => _bpm = v),
        ),
      ],
    );
  }
}
