

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
library;
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/studio_request.dart';
import '../../../data/models/studio_type.dart';
import '../audio/music_request_sheet.dart';
import '../audio/voice_avatar_request_sheet.dart';
import '../copy/copy_scripts_request_sheet.dart';
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


class CodeRequestSheet extends StatefulWidget {
  const CodeRequestSheet({super.key});

  @override
  State<CodeRequestSheet> createState() => _CodeRequestSheetState();
}


class _CodeRequestSheetState extends State<CodeRequestSheet> {
  final _promptController = TextEditingController();
  String _language = 'Python';
  bool _includeComments = true;

  static const _languages = ['Python', 'JavaScript', 'TypeScript', 'Dart', 'Swift', 'SQL', 'HTML'];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      studioType: StudioType.codeStudio,
      canSubmit: _promptController.text.trim().isNotEmpty,
      onSubmit: () => Navigator.of(context).pop(
        CodeRequest(
          prompt: _promptController.text.trim(),
          language: _language,
          includeComments: _includeComments,
        ),
      ),
      fields: [
        TextField(
          controller: _promptController,
          decoration: const InputDecoration(hintText: 'What should this code do?'),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        ChipSelector(
          label: 'Language',
          options: _languages,
          selected: _language,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _language = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include comments'),
          subtitle: const Text('Docstring/comment lines explaining the code'),
          value: _includeComments,
          onChanged: (v) => setState(() => _includeComments = v),
        ),
      ],
    );
  }
}
