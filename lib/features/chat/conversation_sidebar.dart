import '../../core/theme/studio_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/conversation.dart';
import '../../data/models/project.dart';
import 'conversation_export.dart';
import '../../data/stores/conversation_store.dart';
import '../../data/stores/project_store.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../projects/project_detail_sheet.dart';

class ConversationSidebar extends StatefulWidget {
  /// Called after "New chat" is pressed or a conversation is selected —
  /// lets an embedding drawer close itself and switch to the Chat tab.
  final VoidCallback? onActivated;

  const ConversationSidebar({super.key, this.onActivated});

  @override
  State<ConversationSidebar> createState() => _ConversationSidebarState();
}

class _ConversationSidebarState extends State<ConversationSidebar> {
  String _query = '';
  bool _showArchived = false;

  /// Buckets a conversation by how recently it was last touched, matching
  /// Claude's Today / Yesterday / Previous-N-days grouping.
  static String _dateBucket(DateTime updated) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(updated.year, updated.month, updated.day);
    final diff = today.difference(d).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff <= 7) return 'Previous 7 days';
    if (diff <= 30) return 'Previous 30 days';
    return 'Older';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConversationStore>();
    final projectStore = context.watch<ProjectStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    final results = store.search(_query);
    final visible = results.where((c) => !c.archived).toList();
    final archived = results.where((c) => c.archived).toList();
    final pinned = visible.where((c) => c.pinned).toList();
    final starred =
        visible.where((c) => c.starred && !c.pinned).toList();
    final rest =
        visible.where((c) => !c.pinned && !c.starred).toList();

    _ConversationTile tileFor(Conversation c) => _ConversationTile(
          conversation: c,
          project: projectStore.projectById(c.projectId),
          selected: c.id == store.current?.id,
          onActivated: widget.onActivated,
        );

    // Build the date-grouped "recents" with a header before each new bucket.
    final grouped = <Widget>[];
    String? lastBucket;
    for (final c in rest) {
      final bucket = _dateBucket(c.updatedAt);
      if (bucket != lastBucket) {
        grouped.add(_SectionHeader(label: bucket));
        lastBucket = bucket;
      }
      grouped.add(tileFor(c));
    }

    // No outer sizing/background of its own — this is pure scrollable
    // content, laid out inside the enclosing AppSidebar's glass panel (which
    // owns the width, background, and border).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: FilledButton.tonalIcon(
            onPressed: () {
              store.startNewConversation(
                projectId: projectStore.activeProjectId,
              );
              widget.onActivated?.call();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('New chat'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search chats…',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _ProjectsSection(projectStore: projectStore),
              if (pinned.isNotEmpty) ...[
                const _SectionHeader(label: 'Pinned'),
                for (final conversation in pinned) tileFor(conversation),
              ],
              if (starred.isNotEmpty) ...[
                const _SectionHeader(label: 'Starred'),
                for (final conversation in starred) tileFor(conversation),
              ],
              ...grouped,
              if (archived.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _showArchived = !_showArchived),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Archived (${archived.length})',
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        Icon(
                          _showArchived
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showArchived)
                  for (final conversation in archived) tileFor(conversation),
              ],
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    _query.isEmpty
                        ? 'Your conversations will show up here.'
                        : 'No chats match "$_query".',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Projects list: the active project scopes new chats and layers its
/// instructions/knowledge into every turn's system prompt.
class _ProjectsSection extends StatelessWidget {
  final ProjectStore projectStore;

  const _ProjectsSection({required this.projectStore});

  Future<void> _createProject(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final project = projectStore.createProject(name.trim());
    if (context.mounted) {
      showProjectDetailSheet(context, project.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Text('Projects', style: theme.textTheme.labelSmall),
              const Spacer(),
              IconButton(
                tooltip: 'New project',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _createProject(context),
              ),
            ],
          ),
        ),
        for (final project in projectStore.projects)
          ListTile(
            dense: true,
            selected: project.id == projectStore.activeProjectId,
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: project.color,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              project.name,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Project settings',
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              color: colors.textSecondary,
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showProjectDetailSheet(context, project.id),
            ),
            onTap: () => projectStore.setActiveProject(
              project.id == projectStore.activeProjectId ? null : project.id,
            ),
          ),
        if (projectStore.projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Group chats under shared instructions and knowledge.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final Project? project;
  final bool selected;
  final VoidCallback? onActivated;

  const _ConversationTile({
    required this.conversation,
    required this.project,
    required this.selected,
    this.onActivated,
  });

  Future<void> _rename(BuildContext context) async {
    final store = context.read<ConversationStore>();
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (title != null) store.renameConversation(conversation.id, title);
  }

  Future<void> _moveToProject(BuildContext context) async {
    final store = context.read<ConversationStore>();
    final projects = context.read<ProjectStore>().projects;
    final selectedId = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move to project'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('No project'),
          ),
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(project.id),
              child: Text(project.name),
            ),
        ],
      ),
    );
    if (selectedId == null) return;
    store.setConversationProject(
      conversation.id,
      selectedId.isEmpty ? null : selectedId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<ConversationStore>();
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        dense: true,
        leading: project != null
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: project!.color,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        title: Text(
          conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        onTap: () {
          store.selectConversation(conversation.id);
          onActivated?.call();
        },
        trailing: PopupMenuButton<String>(
          tooltip: 'Chat options',
          iconSize: 16,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          onSelected: (action) {
            switch (action) {
              case 'rename':
                _rename(context);
              case 'pin':
                store.togglePin(conversation.id);
              case 'star':
                store.toggleStar(conversation.id);
              case 'archive':
                store.toggleArchive(conversation.id);
              case 'project':
                _moveToProject(context);
              case 'export_md':
                ConversationExport.downloadMarkdown(conversation);
              case 'export_json':
                ConversationExport.downloadJson(conversation);
              case 'export_pdf':
                ConversationExport.exportPdf(conversation);
              case 'delete':
                store.deleteConversation(conversation.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
              value: 'pin',
              child: Text(conversation.pinned ? 'Unpin' : 'Pin'),
            ),
            PopupMenuItem(
              value: 'star',
              child: Text(conversation.starred ? 'Unstar' : 'Star'),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(conversation.archived ? 'Unarchive' : 'Archive'),
            ),
            const PopupMenuItem(
              value: 'project',
              child: Text('Move to project…'),
            ),
            const PopupMenuItem(
              value: 'export_md',
              child: Text('Export as Markdown'),
            ),
            const PopupMenuItem(
              value: 'export_json',
              child: Text('Export as JSON'),
            ),
            const PopupMenuItem(
              value: 'export_pdf',
              child: Text('Export as PDF'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
