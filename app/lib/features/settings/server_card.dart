import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/setup_probe.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/account_store.dart';

/// What SHIFT's own server is doing, and whether it is the server this app
/// expects.
///
/// **Everything on this card already existed and nothing could reach it.**
/// `testProxy` and `readProxyResponse` were written across two waves, tested,
/// and had zero callers in v2 — so the diagnostics built to tell "not
/// deployed" from "not entitled" from "the key is wrong" were unreachable from
/// the app actually being used, and the loop stayed *"send a turn and describe
/// what you saw"*.
///
/// The routes row is the one that could not have existed before. Every other
/// check in this app compares the client to the server's allowlist **in this
/// repository**, which stayed green for a week while the deployed proxy was
/// five commits behind and refusing every image. This asks the running server.
class ServerCard extends StatefulWidget {
  const ServerCard({super.key});

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> {
  RoutesReport? _routes;
  ProxyProbeResult? _probe;

  /// Which provider is being tested, so only its own button shows the wait.
  String? _testing;
  bool _checkingRoutes = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    if (!store.isConfigured || !store.isSignedIn) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final covered = store.includedProviders;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server', style: text.titleMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),
          Text(
            'What SHIFT\'s own server will do for this account.',
            style: text.bodySmall?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.md),

          _row(
            c,
            text,
            'Covered by your plan',
            covered.isEmpty
                ? 'Nothing yet. A plan covers whichever providers SHIFT holds '
                    'keys for.'
                : covered.join(', '),
          ),
          const SizedBox(height: Space.md),

          _routesRow(c, text),
          const SizedBox(height: Space.md),

          _testRow(store, c, text, covered),
        ],
      ),
    );
  }

  Widget _row(ShiftColors c, TextTheme text, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),
          Text(value, style: text.bodySmall?.copyWith(color: c.textMuted)),
        ],
      );

  /// Whether the deployed proxy forwards what this app sends.
  ///
  /// Its missing routes are listed rather than counted. "The server is behind"
  /// is what the last week's failed turns already said; *which* route is the
  /// part that names the fix.
  Widget _routesRow(ShiftColors c, TextTheme text) {
    final report = _routes;
    final tone = switch (report?.outcome) {
      null => c.textMuted,
      RoutesOutcome.current => c.textMuted,
      RoutesOutcome.behind || RoutesOutcome.older => c.danger,
      RoutesOutcome.unknown => c.textMuted,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Server routes',
                  style: text.labelMedium?.copyWith(color: c.text)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: TextButton(
                onPressed: _checkingRoutes ? null : _checkRoutes,
                child: Text(_checkingRoutes ? 'Checking…' : 'Check',
                    style: text.labelLarge?.copyWith(color: c.accent)),
              ),
            ),
          ],
        ),
        Text(
          report?.message ??
              'Not checked. This is what says whether the deployed server is '
                  'the one this app expects.',
          style: text.bodySmall?.copyWith(color: tone),
        ),
        if (report != null && report.missing.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          for (final route in report.missing)
            Text(route,
                style: text.bodySmall?.copyWith(
                  color: c.textMuted,
                  fontFamily: 'monospace',
                )),
        ],
        if (report?.version case final version?) ...[
          const SizedBox(height: Space.xxs),
          Text('Server build $version',
              style: text.bodySmall?.copyWith(color: c.textMuted)),
        ],
      ],
    );
  }

  /// One real call through the proxy, per provider the plan covers.
  ///
  /// Offered only for a covered provider: a test that is refused for the one
  /// reason we already know about teaches nothing, and a button that always
  /// fails is worse than no button.
  Widget _testRow(AccountStore store, ShiftColors c, TextTheme text,
      List<String> covered) {
    final result = _probe;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Test connection',
            style: text.labelMedium?.copyWith(color: c.text)),
        const SizedBox(height: Space.xxs),
        Text(
          result?.message ??
              'Sends one small real call through the server and says which of '
                  'the states it hit.',
          style: text.bodySmall?.copyWith(
              color: result == null || result.isWorking ? c.textMuted : c.danger),
        ),
        if (covered.isEmpty)
          const SizedBox.shrink()
        else ...[
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final provider in covered)
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: kMinTouchTarget),
                  child: TextButton(
                    onPressed: _testing != null
                        ? null
                        : () => _test(store, provider),
                    child: Text(
                      _testing == provider ? 'Testing…' : provider,
                      style: text.labelLarge?.copyWith(color: c.accent),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _checkRoutes() async {
    setState(() => _checkingRoutes = true);
    final report = await context.read<AccountStore>().checkProxyRoutes();
    if (!mounted) return;
    setState(() {
      _routes = report;
      _checkingRoutes = false;
    });
  }

  Future<void> _test(AccountStore store, String provider) async {
    setState(() => _testing = provider);
    final result = await store.testProxy(provider: provider);
    if (!mounted) return;
    setState(() {
      _probe = result;
      _testing = null;
    });
  }
}
