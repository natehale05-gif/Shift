import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../providers/registry.dart';

/// One provider's row: what it can do, where to get a key, and the key.
class ProviderKeyField extends StatefulWidget {
  final ProviderDescriptor provider;

  /// The stored key, masked. Null when there is none.
  final String? saved;

  final ValueChanged<String> onSave;
  final VoidCallback onRemove;

  const ProviderKeyField({
    super.key,
    required this.provider,
    required this.saved,
    required this.onSave,
    required this.onRemove,
  });

  @override
  State<ProviderKeyField> createState() => _ProviderKeyFieldState();
}

class _ProviderKeyFieldState extends State<ProviderKeyField> {
  final _controller = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

          if (saved != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    saved,
                    style: text.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                ),
                TextButton(
                  onPressed: widget.onRemove,
                  child: Text('Remove',
                      style: text.labelLarge?.copyWith(color: c.danger)),
                ),
              ],
            )
          else ...[
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
