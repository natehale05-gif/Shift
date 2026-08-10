import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../providers/access.dart';
import '../../providers/probe.dart';
import '../../providers/registry.dart';

/// One provider's row: what it can do, where to get a key, and the key.
class ProviderKeyField extends StatefulWidget {
  final ProviderDescriptor provider;

  /// The stored key, masked. Null when there is none.
  final String? saved;

  final ValueChanged<String> onSave;
  final VoidCallback onRemove;

  /// The real key, for the connection test. Read lazily rather than held, so
  /// nothing in this widget's state is the secret itself.
  final String? Function()? readKey;

  /// Injected so the test's own states can be driven without a network. Every
  /// sentence it can produce is unreproducible in a sandbox — CORS does not
  /// exist off-web, and off-web is where every test runs.
  final Future<ProbeOutcome> Function(ProviderAccess access)? probe;

  const ProviderKeyField({
    super.key,
    required this.provider,
    required this.saved,
    required this.onSave,
    required this.onRemove,
    this.readKey,
    this.probe,
  });

  @override
  State<ProviderKeyField> createState() => _ProviderKeyFieldState();
}

class _ProviderKeyFieldState extends State<ProviderKeyField> {
  final _controller = TextEditingController();
  String? _problem;

  bool _testing = false;
  ProbeOutcome? _outcome;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sends one real request and reports which of the states it hit.
  ///
  /// This is the control that turns "it says it cannot reach the provider" into
  /// an answer. A failed chat turn cannot distinguish a dead key from a blocked
  /// request; this can, because it asks the reachability probe too.
  Future<void> _test() async {
    final key = widget.readKey?.call();
    if (key == null || key.isEmpty) return;

    setState(() {
      _testing = true;
      _outcome = null;
    });

    final run = widget.probe ??
        (access) => runProbe(providerId: widget.provider.id, access: access);
    final outcome = await run(DirectKey(key));

    if (!mounted) return;
    setState(() {
      _testing = false;
      _outcome = outcome;
    });
  }

  void _save() {
    final raw = _controller.text;
    final clean = raw.replaceAll(RegExp(r'\s'), '');

    if (clean.isEmpty) {
      setState(() => _problem = 'Paste a key first.');
      return;
    }

    // Checked before anything is sent. A truncated paste otherwise costs a
    // network round trip and comes back as a 401, which reads as "my key is
    // wrong" when the truth is "my key is incomplete" — a different problem
    // with a different fix.
    final shape = widget.provider.keyShape;
    if (shape != null && !shape.hasMatch(clean)) {
      setState(() => _problem =
          "That does not look like a ${widget.provider.displayName} key. "
          'Check you copied the whole thing.');
      return;
    }

    setState(() => _problem = null);
    _controller.clear();
    widget.onSave(clean);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final saved = widget.saved;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.provider.displayName,
                    style: text.titleMedium?.copyWith(color: c.text)),
              ),
              if (saved != null)
                Icon(Icons.check_circle_rounded, size: 18, color: c.accent),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            widget.provider.can.map((it) => it.name).join(' · '),
            style: text.labelMedium?.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: Space.md),

          if (saved != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    saved,
                    style: text.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                ),
                if (canProbe(widget.provider))
                  TextButton(
                    onPressed: _testing ? null : _test,
                    child: Text(
                      _testing ? 'Testing…' : 'Test connection',
                      style: text.labelLarge?.copyWith(color: c.accent),
                    ),
                  ),
                TextButton(
                  onPressed: widget.onRemove,
                  child: Text('Remove',
                      style: text.labelLarge?.copyWith(color: c.danger)),
                ),
              ],
            ),
            if (_outcome case final outcome?) ...[
              const SizedBox(height: Space.xs),
              Text(
                probeSentence(outcome),
                style: text.bodySmall?.copyWith(
                  color: outcome == ProbeOutcome.working ? c.accent : c.textMuted,
                ),
              ),
            ],
          ] else ...[
            TextField(
              controller: _controller,
              // Obscured while typing: this is a secret, and on a phone it is
              // typed in public as often as not.
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: text.bodyMedium?.copyWith(color: c.text),
              cursorColor: c.accent,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Paste your key',
                hintStyle: text.bodyMedium?.copyWith(color: c.textFaint),
                errorText: _problem,
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                // Small, and it matters: the difference between pasting a key
                // in a minute and giving up is knowing where it comes from.
                Text(widget.provider.keyUrl.host,
                    style: text.labelMedium?.copyWith(color: c.textFaint)),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
