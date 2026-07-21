import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/project.dart';
import '../../state/conversation_store.dart';
import '../../state/project_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Bottom sheet for editing a project: name, custom instructions, and
/// text knowledge documents.
Future<void> showProjectDetailSheet(BuildContext context, String projectId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ProjectDetailSheet(projectId: projectId),
  );
}

class _ProjectDetailSheet extends StatefulWidget {
  final String projectId;

  const _ProjectDetailSheet({required this.projectId});

  @override
  State<_ProjectDetailSheet> createState() => _ProjectDetailSheetState();
}

class _ProjectDetailSheetState extends State<_ProjectDetailSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    final project =
        context.read<ProjectStore>().projectById(widget.projectId);
    _nameController = TextEditingController(text: project?.name ?? '');
    _instructionsController =
        TextEditingController(text: project?.customInstructions ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _save(ProjectStore store, Project project) {
    store.updateProject(project.copyWith(
      name: _nameController.text.trim().isEmpty
          ? project.name
          : _nameController.text.trim(),
      customInstructions: _instructionsController.text,
    ));
  }

  Future<void> _addKnowledge(ProjectStore store, Project project) async {
    final nameController = TextEditingController();
    final textController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add knowledge'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Document name (e.g. Brand voice)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: textController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                    hintText: 'Paste the content the AI should always know…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added != true) return;
    final name = nameController.text.trim();
    final text = textController.text.trim();
    if (name.isEmpty || text.isEmpty) return;
    store.updateProject(project.copyWith(
      knowledge: [...project.knowledge, KnowledgeDoc(name: name, text: text)],
    ));
  }

  /// Adds one or more text files (their contents become knowledge the AI
  /// always sees for this project's chats).
  Future<void> _uploadKnowledge(ProjectStore store, Project project) async {
    const typeGroup = XTypeGroup(
      label: 'Text files',
      extensions: [
        'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml',
        'html', 'css', 'js', 'ts', 'dart', 'py', 'xml',
      ],
    );
    final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
    if (files.isEmpty) return;
    final docs = <KnowledgeDoc>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) continue;
      docs.add(KnowledgeDoc(name: file.name, text: text));
    }
    if (docs.isEmpty) return;
    store.updateProject(
      project.copyWith(knowledge: [...project.knowledge, ...docs]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final project = store.projectById(widget.projectId);
    final theme = Theme.of(context);

    if (project == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: project.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Project settings',
                  style: AppTypography.serifDisplay(
                    fontSize: 22,
                    color: theme.textTheme.headlineMedium!.color!,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    store.deleteProject(project.id);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => _save(store, project),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _instructionsController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Custom instructions',
                hintText: 'How should SHIFT AI behave in this project? '
                    '(Make it a persona to use this as a Gem.)',
              ),
              onChanged: (_) => _save(store, project),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text('Knowledge', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _uploadKnowledge(store, project),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload'),
                ),
                TextButton.icon(
                  onPressed: () => _addKnowledge(store, project),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Paste'),
                ),
              ],
            ),
            if (project.knowledge.isEmpty)
              Text(
                'Text documents the AI always has in context for this '
                'project\'s chats.',
                style: theme.textTheme.bodySmall,
              ),
            for (var i = 0; i < project.knowledge.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined, size: 18),
                title: Text(project.knowledge[i].name),
                subtitle: Text(
                  '${project.knowledge[i].text.length} characters',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: IconButton(
                  tooltip: 'Remove',
                  iconSize: 16,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    final knowledge = [...project.knowledge]..removeAt(i);
                    store.updateProject(
                        project.copyWith(knowledge: knowledge));
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text('Chats in this project', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Builder(
              builder: (context) {
                final chats = context
                    .watch<ConversationStore>()
                    .conversations
                    .where((c) => c.projectId == project.id && !c.archived)
                    .toList();
                if (chats.isEmpty) {
                  return Text(
                    'No chats yet. New chats you start while this project is '
                    'active will be filed here.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final chat in chats)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        title: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          context
                              .read<ConversationStore>()
                              .selectConversation(chat.id);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
