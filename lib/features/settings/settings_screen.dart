import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/memory_entry.dart';
import 'app_data_export.dart';
import '../../data/stores/app_settings_store.dart';
import '../../data/stores/conversation_store.dart';
import '../../data/stores/memory_store.dart';
import '../../data/stores/project_store.dart';
import '../../data/stores/styles_store.dart';
import '../../data/stores/user_prefs_store.dart';
import '../styles/style_editor.dart';
import '../../core/theme/app_spacing.dart';
import 'api_keys_section.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/shell/home_menu_button.dart';
import '../../core/platform/open_url.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    final colors = Theme.of(context).extension<AppSemanticColors>()!;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Settings'),
        leading: const HomeMenuButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionCard(
            title: 'Appearance',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => settings.setThemeMode(selection.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionCard(
            title: 'API keys (live AI)',
            child: ApiKeysSection(),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _PersonalizationCard(),
          const SizedBox(height: AppSpacing.lg),
          const _StylesCard(),
          const SizedBox(height: AppSpacing.lg),
          const _MemoryCard(),
          const SizedBox(height: AppSpacing.lg),
          const _GetTheAppCard(),
          const SizedBox(height: AppSpacing.lg),
          const _FeaturePreviewCard(),
          const SizedBox(height: AppSpacing.lg),
          _SectionCard(
            title: 'Data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Everything — chats, projects, memory, preferences, and keys — '
                  'is stored only in this browser. There\'s no account and no '
                  'server. Export a full copy, or sign out to wipe it all.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _exportAll(context),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Export all data (.zip)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _confirmClear(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Clear chat history'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out & erase everything'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionCard(
            title: 'About',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SHIFT AI', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'A middleware AI that routes your requests to specialized studios — Image, Video, Voice & Avatar, Music, Copy & Scripts, and Code. '
                  'This build is a local prototype: chat replies and studio results are simulated. Images, audio, and code are downloadable as real files. '
                  'Membership/EcoPay screens are illustrative demos only — no real purchases, credits, or payouts occur anywhere in this app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('shiftai.club', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text('This removes every conversation stored in this browser. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              context.read<ConversationStore>().clearAllHistory();
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _exportAll(BuildContext context) {
    AppDataExport.download(
      conversations: context.read<ConversationStore>().conversations,
      projects: context.read<ProjectStore>().projects,
      preferences: {
        'nickname': context.read<UserPrefsStore>().nickname,
        'role': context.read<UserPrefsStore>().role,
        'traits': context.read<UserPrefsStore>().traits,
        'responseStyle': context.read<UserPrefsStore>().responseStyle,
        'customInstructions':
            context.read<UserPrefsStore>().customInstructions,
      },
      memory: context.read<MemoryStore>().entries,
      memoryEnabled: context.read<MemoryStore>().enabled,
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out & erase everything?'),
        content: const Text(
          'This permanently deletes every chat, project, memory, and '
          'preference stored in this browser. Export your data first if you '
          'want to keep it. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              final prefs = context.read<UserPrefsStore>();
              final projects = context.read<ProjectStore>();
              context.read<ConversationStore>().clearAllHistory();
              for (final p in [...projects.projects]) {
                projects.deleteProject(p.id);
              }
              context.read<MemoryStore>().clearAll();
              prefs.setNickname('');
              prefs.setRole('');
              prefs.setTraits('');
              prefs.setCustomInstructions('');
              prefs.setResponseStyle('normal');
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
  }
}

/// Feature-preview toggles (Claude's "Feature preview" settings).
/// Desktop and Android downloads, for people who found the app in a browser.
/// Hidden on the desktop/Android builds themselves — you already have it.
class _GetTheAppCard extends StatelessWidget {
  const _GetTheAppCard();

  static const _releases =
      'https://github.com/natehale05-gif/Shift/releases/latest';

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Get the app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Native builds for macOS, Windows, Linux and Android. Chats are '
            'kept on your device between launches.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (label, icon) in const [
                ('macOS', Icons.laptop_mac_rounded),
                ('Windows', Icons.desktop_windows_rounded),
                ('Linux', Icons.dns_rounded),
                ('Android', Icons.phone_android_rounded),
              ])
                OutlinedButton.icon(
                  onPressed: () => openUrl(_releases),
                  icon: Icon(icon, size: 18),
                  label: Text(label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturePreviewCard extends StatelessWidget {
  const _FeaturePreviewCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    return _SectionCard(
      title: 'Feature preview',
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show usage & token counts'),
        subtitle: Text(
          'Display the model and input/output token tally under each reply.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: settings.showUsage,
        onChanged: settings.setShowUsage,
      ),
    );
  }
}

/// The "memory" layer: nickname, response style, and standing custom
/// instructions, folded into every turn's system prompt.
class _PersonalizationCard extends StatefulWidget {
  const _PersonalizationCard();

  @override
  State<_PersonalizationCard> createState() => _PersonalizationCardState();
}

class _PersonalizationCardState extends State<_PersonalizationCard> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _roleController;
  late final TextEditingController _traitsController;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<UserPrefsStore>();
    _nicknameController = TextEditingController(text: prefs.nickname);
    _roleController = TextEditingController(text: prefs.role);
    _traitsController = TextEditingController(text: prefs.traits);
    _instructionsController =
        TextEditingController(text: prefs.customInstructions);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _roleController.dispose();
    _traitsController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefsStore>();
    return _SectionCard(
      title: 'Personalization',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SHIFT AI carries these preferences into every conversation.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: 'What should SHIFT AI call you?',
            ),
            onChanged: prefs.setNickname,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _roleController,
            decoration: const InputDecoration(
              labelText: 'What do you do?',
              hintText: 'e.g. product designer, high-school teacher, founder',
            ),
            onChanged: prefs.setRole,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _traitsController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What traits should SHIFT AI have?',
              hintText: 'e.g. direct, encouraging, uses analogies',
            ),
            onChanged: prefs.setTraits,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', label: Text('Normal')),
                ButtonSegment(value: 'concise', label: Text('Concise')),
                ButtonSegment(
                    value: 'explanatory', label: Text('Explanatory')),
                ButtonSegment(value: 'formal', label: Text('Formal')),
              ],
              selected: {prefs.responseStyle},
              onSelectionChanged: (selection) =>
                  prefs.setResponseStyle(selection.first),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _instructionsController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Custom instructions',
              hintText:
                  'Standing guidance for every chat (tone, interests, context)…',
            ),
            onChanged: prefs.setCustomInstructions,
          ),
        ],
      ),
    );
  }
}

/// Custom response styles: the built-in set (read-only) plus user-created
/// styles with create/edit/delete (Claude's custom styles).
class _StylesCard extends StatelessWidget {
  const _StylesCard();

  Future<void> _create(BuildContext context) async {
    final result = await showStyleEditorDialog(context);
    if (result == null || !context.mounted) return;
    context.read<StylesStore>().create(result.$1, result.$2);
  }

  Future<void> _edit(BuildContext context, String id, String name,
      String instructions) async {
    final result = await showStyleEditorDialog(
      context,
      initialName: name,
      initialInstructions: instructions,
    );
    if (result == null || !context.mounted) return;
    context
        .read<StylesStore>()
        .update(id, name: result.$1, instructions: result.$2);
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.watch<StylesStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return _SectionCard(
      title: 'Response styles',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Built-in: Normal, Concise, Explanatory, Formal. Create your '
                  'own and pick it from the composer\'s Style menu.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New style'),
              ),
            ],
          ),
          if (styles.customStyles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'No custom styles yet.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
          for (final style in styles.customStyles)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.brush_outlined, size: 18),
              title: Text(style.name),
              subtitle: Text(
                style.instructions,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    iconSize: 16,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(
                        context, style.id, style.name, style.instructions),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    iconSize: 16,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => context.read<StylesStore>().remove(style.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Cross-chat memory: a master switch plus the list of remembered facts, each
/// toggleable, editable, and removable (Claude's Memory settings).
class _MemoryCard extends StatelessWidget {
  const _MemoryCard();

  Future<void> _edit(BuildContext context, MemoryEntry entry) async {
    final store = context.read<MemoryStore>();
    final controller = TextEditingController(text: entry.text);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit memory'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      store.editEntry(entry.id, text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = context.watch<MemoryStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return _SectionCard(
      title: 'Memory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SHIFT AI remembers useful facts about you across chats and '
                  'brings them into future replies.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(value: memory.enabled, onChanged: memory.setEnabled),
            ],
          ),
          if (memory.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Nothing remembered yet. Tell SHIFT AI something about '
                'yourself — like your name, where you live, or what you do — '
                'and it\'ll appear here.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final entry in memory.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: entry.enabled,
                onChanged: (_) => memory.toggleEntry(entry.id),
              ),
              title: Text(
                entry.text,
                style: entry.enabled
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    iconSize: 16,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, entry),
                  ),
                  IconButton(
                    tooltip: 'Forget',
                    iconSize: 16,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => memory.removeEntry(entry.id),
                  ),
                ],
              ),
            ),
          if (memory.entries.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: memory.clearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear all'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
