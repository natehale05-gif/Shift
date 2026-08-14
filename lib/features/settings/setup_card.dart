import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../backend/shift_backend.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/open_url.dart';
import '../../data/account_store.dart';

/// The settings only a person with a dashboard login can change, each one a
/// tap and a paste rather than an instruction.
///
/// **This card is the missing half of the sentence above it.** The Server
/// card's own diagnosis reads *"…use the server settings below, then push any
/// commit"* — and there was nothing below. `setupLinks()` had been written,
/// tested, and exposed on the store with **zero callers**, so the app named the
/// exact blocker it was stuck on and then showed no way to clear it. That is
/// the same shape as `testProxy` having no caller until the Server card was
/// built; this is the layer above it.
///
/// Every row carries a **copy** button, because the values are a secret name, a
/// project ref and a URL, and the device most likely to be reading this is a
/// phone. Typing `SUPABASE_ACCESS_TOKEN` into a GitHub form with a thumb is how
/// a setup step gets abandoned.
class SetupCard extends StatelessWidget {
  const SetupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    // Same gate as the Server card it sits under: these are the project's own
    // settings, so they are the owner's business and not a visitor's.
    if (!store.isConfigured || !store.isSignedIn) return const SizedBox.shrink();

    final links = store.setupLinks;
    if (links.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;

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
          Text('Server settings',
              style: text.titleMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),
          Text(
            'Things no code in this app can set for you. Each one opens the '
            'right page with the value on your clipboard.',
            style: text.bodySmall?.copyWith(color: c.textMuted),
          ),
          for (final link in links) ...[
            const SizedBox(height: Space.md),
            _SetupRow(link: link),
          ],
        ],
      ),
    );
  }
}

class _SetupRow extends StatefulWidget {
  final SetupLink link;

  const _SetupRow({required this.link});

  @override
  State<_SetupRow> createState() => _SetupRowState();
}

class _SetupRowState extends State<_SetupRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.link.copyValue));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final link = widget.link;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(link.title, style: text.labelMedium?.copyWith(color: c.text)),
        const SizedBox(height: Space.xxs),
        // The value itself, in the mono face, so it is checkable against what
        // was pasted rather than taken on trust.
        Text(
          '${link.copyLabel}: ${link.copyValue}',
          style: text.bodySmall
              ?.copyWith(color: c.textMuted, fontFamily: 'monospace'),
        ),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.sm,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: TextButton(
                onPressed: () => openUrl(link.url.toString()),
                child: Text(link.action,
                    style: text.labelLarge?.copyWith(color: c.accent)),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: TextButton(
                onPressed: _copy,
                child: Text(
                  _copied ? 'Copied' : 'Copy ${link.copyLabel.toLowerCase()}',
                  style: text.labelLarge
                      ?.copyWith(color: _copied ? c.success : c.accent),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
