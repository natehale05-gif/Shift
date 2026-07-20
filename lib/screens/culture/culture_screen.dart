import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/glass_app_bar.dart';
import '../../widgets/common/home_menu_button.dart';

class _CultureEvent {
  final IconData icon;
  final String cadence;
  final String title;

  const _CultureEvent({required this.icon, required this.cadence, required this.title});
}

const _events = [
  _CultureEvent(
    icon: Icons.emoji_events_outlined,
    cadence: 'ANNUAL CONVENTIONS',
    title: 'The Inner Circle',
  ),
  _CultureEvent(
    icon: Icons.leaderboard_outlined,
    cadence: 'WEEKLY CONTEST',
    title: 'Cash + Experiences',
  ),
  _CultureEvent(
    icon: Icons.nightlife_outlined,
    cadence: 'NIGHTLY LIVE CONNECTIONS',
    title: 'Meet Other Club Members',
  ),
  _CultureEvent(
    icon: Icons.flight_takeoff_outlined,
    cadence: 'QUARTERLY TRIPS',
    title: 'Exotic Destinations',
  ),
  _CultureEvent(
    icon: Icons.groups_2_outlined,
    cadence: 'WEEKLY SOCIALS',
    title: 'Worldwide',
  ),
];

/// A static, informational screen summarizing the "Culture" pillar from
/// shiftai.club. No photos of real people/events are fabricated here —
/// represented with icons instead.
class CultureScreen extends StatelessWidget {
  const CultureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Culture'),
        leading: MediaQuery.sizeOf(context).width < 720
            ? const HomeMenuButton()
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("It's not just an AI platform. It's a club.", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The SHIFT AI Club puts members in the room with the right people, at the right time.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final event in _events)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(event.icon, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.cadence,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.6),
                          ),
                          Text(event.title, style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
