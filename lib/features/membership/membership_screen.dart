import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/membership_tier.dart';
import '../../data/stores/app_settings_store.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/disclaimer_banner.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/shell/home_menu_button.dart';
import 'payout_stream_card.dart';
import 'tier_card.dart';
// Deferred: the EcoPay tab is the app's only fl_chart consumer, and it
// sits behind a tab the user has to choose. Splitting it keeps the
// charting library out of the initial download.
import 'ecopay_calculator_screen.dart' deferred as ecopay;

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GlassAppBar(
          title: const Text('Membership & EcoPay'),
          leading: const HomeMenuButton(),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Plans'),
              Tab(text: 'EcoPay Calculator'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PlansTab(),
            _DeferredEcopayTab(),
          ],
        ),
      ),
    );
  }
}

class _PlansTab extends StatelessWidget {
  const _PlansTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pick your Club Membership', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Demo only — selecting a plan here never charges you or makes a real purchase.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.lg,
                crossAxisSpacing: AppSpacing.lg,
                childAspectRatio: columns == 2 ? 1.15 : 1.5,
                children: [
                  for (final tier in MembershipTier.all)
                    TierCard(
                      tier: tier,
                      isSelected: settings.selectedTier?.id == tier.id,
                      onSimulateSelect: () => settings.simulateSelectTier(tier.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('EcoPay earning streams', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          const DisclaimerBanner(),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: columns == 2 ? 2.4 : 2.6,
                children: [
                  for (final stream in PayoutStream.all) PayoutStreamCard(stream: stream),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Loads the EcoPay calculator (and with it `fl_chart`) the first time the tab
/// is shown, rather than shipping the charting library in the initial bundle.
class _DeferredEcopayTab extends StatelessWidget {
  const _DeferredEcopayTab();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ecopay.loadLibrary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text("Couldn't load the calculator."));
        }
        return ecopay.EcopayCalculatorScreen();
      },
    );
  }
}
