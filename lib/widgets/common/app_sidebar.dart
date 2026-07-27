import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/stores/user_prefs_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../features/chat/conversation_sidebar.dart';
import 'liquid_glass.dart';

class SidebarDestination {
  final IconData icon;
  final String label;

  const SidebarDestination({required this.icon, required this.label});
}

/// Destinations reachable from the profile button, in [HomeShell]'s
/// IndexedStack order starting at index 1 (index 0 is Chat, which the
/// sidebar's own conversation list already handles).
const List<SidebarDestination> profileMenuDestinations = [
  SidebarDestination(
    icon: Icons.workspace_premium_rounded,
    label: 'Membership',
  ),
  SidebarDestination(icon: Icons.groups_rounded, label: 'Culture'),
  SidebarDestination(icon: Icons.settings_rounded, label: 'Settings'),
];

/// The app's single navigation surface — a Liquid Glass panel with the
/// brand header up top, chat history filling the middle (via
/// [ConversationSidebar]), and a bottom-pinned circular profile button that
/// opens Membership/Culture/Settings. Mirrors the Claude-app pattern of
/// keeping every account-level destination behind one avatar menu instead
/// of a separate always-visible icon rail.
class AppSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigate;

  /// Called after a destination is chosen — lets an embedding Drawer close
  /// itself.
  final VoidCallback? onActivated;

  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
    this.onActivated,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return LiquidGlass(
      blurSigma: 40,
      tintOpacity: 0.55,
      border: Border(right: BorderSide(color: colors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SidebarHeader(),
          Expanded(
            child: ConversationSidebar(
              onActivated: () {
                onNavigate(0);
                onActivated?.call();
              },
            ),
          ),
          Divider(height: 1, color: colors.border),
          _ProfileButton(
            currentIndex: currentIndex,
            onNavigate: (index) {
              onNavigate(index);
              onActivated?.call();
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accentDark, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('SHIFT AI', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Circular avatar in the bottom-left of the sidebar. Tapping it opens a
/// glass popover, anchored above the button, listing every account-level
/// section that used to live in a separate icon rail.
class _ProfileButton extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigate;

  const _ProfileButton({required this.currentIndex, required this.onNavigate});

  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    final selected = await showMenu<int>(
      context: context,
      position: position,
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        for (var i = 0; i < profileMenuDestinations.length; i++)
          PopupMenuItem<int>(
            value: i + 1, // Chat is index 0; the menu covers 1..3.
            child: _ProfileMenuTile(
              destination: profileMenuDestinations[i],
              selected: currentIndex == i + 1,
            ),
          ),
      ],
    );
    if (selected != null) onNavigate(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final name = context.watch<UserPrefsStore>().nickname.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          onTap: () => _openMenu(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.accentDark, AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: initial != null
                      ? Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    name.isNotEmpty ? name : 'Account',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final SidebarDestination destination;
  final bool selected;

  const _ProfileMenuTile({required this.destination, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Row(
      children: [
        Icon(
          destination.icon,
          size: 18,
          color: selected ? theme.colorScheme.primary : colors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          destination.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
