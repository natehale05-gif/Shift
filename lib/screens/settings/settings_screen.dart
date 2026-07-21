import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/memory_entry.dart';
import '../../state/app_settings_store.dart';
import '../../state/conversation_store.dart';
import '../../state/memory_store.dart';
import '../../state/user_prefs_store.dart';
import '../../theme/app_spacing.dart';
import 'api_keys_section.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/glass_app_bar.dart';
import '../../widgets/common/home_menu_button.dart';

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
          const _MemoryCard(),
          const SizedBox(height: AppSpacing.lg),
          _SectionCard(
            title: 'Data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conversations and demo settings are stored only in this browser — there\'s no account and no server.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear chat history'),
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
