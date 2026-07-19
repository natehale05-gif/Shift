import 'package:flutter/material.dart';

import '../../models/studio_request.dart';
import '../../models/studio_type.dart';
import '../../theme/app_spacing.dart';

/// Opens the structured-input bottom sheet for [studioType] and returns the
/// submitted [StudioRequest], or null if the user dismissed it.
Future<StudioRequest?> showStudioRequestSheet(
  BuildContext context,
  StudioType studioType,
) {
  return showModalBottomSheet<StudioRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => switch (studioType) {
      StudioType.imageStudio => const _ImageRequestSheet(),
      StudioType.videoStudio => const _VideoRequestSheet(),
      StudioType.voiceAvatarStudio => const _VoiceAvatarRequestSheet(),
      StudioType.musicStudio => const _MusicRequestSheet(),
      StudioType.copyScriptsStudio => const _CopyScriptsRequestSheet(),
      StudioType.codeStudio => const _CodeRequestSheet(),
      StudioType.middleware => throw ArgumentError('No sheet for middleware'),
    },
  );
}

class _SheetScaffold extends StatelessWidget {
  final StudioType studioType;
  final List<Widget> fields;
  final VoidCallback onSubmit;
  final bool canSubmit;

  const _SheetScaffold({
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

class _ChipSelector<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T selected;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;

  const _ChipSelector({
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

class _ImageRequestSheet extends StatefulWidget {
  const _ImageRequestSheet();

  @override
  State<_ImageRequestSheet> createState() => _ImageRequestSheetState();
}

class _ImageRequestSheetState extends State<_ImageRequestSheet> {
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
    return _SheetScaffold(
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
        _ChipSelector(
          label: 'Aspect ratio',
          options: _aspectRatios,
          selected: _aspectRatio,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _aspectRatio = v),
        ),
        _ChipSelector(
          label: 'Style',
          options: _styles,
          selected: _style,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _style = v),
        ),
        _ChipSelector(
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

class _VideoRequestSheet extends StatefulWidget {
  const _VideoRequestSheet();

  @override
  State<_VideoRequestSheet> createState() => _VideoRequestSheetState();
}

class _VideoRequestSheetState extends State<_VideoRequestSheet> {
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
    return _SheetScaffold(
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
        _ChipSelector(
          label: 'Duration',
          options: _durations,
          selected: _duration,
          labelBuilder: (v) => '${v}s',
          onSelected: (v) => setState(() => _duration = v),
        ),
        _ChipSelector(
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

class _VoiceAvatarRequestSheet extends StatefulWidget {
  const _VoiceAvatarRequestSheet();

  @override
  State<_VoiceAvatarRequestSheet> createState() => _VoiceAvatarRequestSheetState();
}

class _VoiceAvatarRequestSheetState extends State<_VoiceAvatarRequestSheet> {
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
    return _SheetScaffold(
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
        _ChipSelector(
          label: 'Voice',
          options: _voices,
          selected: _voice,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _voice = v),
        ),
        _ChipSelector(
          label: 'Tone',
          options: _tones,
          selected: _tone,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _tone = v),
        ),
        _ChipSelector(
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

class _MusicRequestSheet extends StatefulWidget {
  const _MusicRequestSheet();

  @override
  State<_MusicRequestSheet> createState() => _MusicRequestSheetState();
}

class _MusicRequestSheetState extends State<_MusicRequestSheet> {
  String _mood = 'Uplifting';
  int _duration = 30;
  double _bpm = 100;

  static const _moods = ['Uplifting', 'Cinematic', 'Lo-fi', 'Corporate'];
  static const _durations = [15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      studioType: StudioType.musicStudio,
      canSubmit: true,
      onSubmit: () => Navigator.of(context).pop(
        MusicRequest(mood: _mood, durationSec: _duration, bpm: _bpm.round()),
      ),
      fields: [
        _ChipSelector(
          label: 'Mood / genre',
          options: _moods,
          selected: _mood,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _mood = v),
        ),
        _ChipSelector(
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

class _CopyScriptsRequestSheet extends StatefulWidget {
  const _CopyScriptsRequestSheet();

  @override
  State<_CopyScriptsRequestSheet> createState() => _CopyScriptsRequestSheetState();
}

class _CopyScriptsRequestSheetState extends State<_CopyScriptsRequestSheet> {
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
    return _SheetScaffold(
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
        _ChipSelector(
          label: 'Content type',
          options: _contentTypes,
          selected: _contentType,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _contentType = v),
        ),
        _ChipSelector(
          label: 'Tone',
          options: _tones,
          selected: _tone,
          labelBuilder: (v) => v,
          onSelected: (v) => setState(() => _tone = v),
        ),
        _ChipSelector(
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

class _CodeRequestSheet extends StatefulWidget {
  const _CodeRequestSheet();

  @override
  State<_CodeRequestSheet> createState() => _CodeRequestSheetState();
}

class _CodeRequestSheetState extends State<_CodeRequestSheet> {
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
    return _SheetScaffold(
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
        _ChipSelector(
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
