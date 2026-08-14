import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/open_url.dart';
import '../../turn/turn_event.dart';
import 'citation_markers.dart';

/// The pages a reply drew on, under the reply.
///
/// Numbered to match the inline markers, from the same [railOrder] list, so a
/// superscript ³ and the third row here are always the same page. Two lists
/// numbered separately would be worse than no numbering at all.
///
/// Shown even when nothing carries an offset — Gemini's grounding returns
/// sources without positions — because *which pages* is worth having on its
/// own. It is the inline marker that needs a position, not the source.
class SourcesRail extends StatelessWidget {
  final List<Citation> citations;

  const SourcesRail({super.key, required this.citations});

  @override
  Widget build(BuildContext context) {
    final sources = railOrder(citations);
    if (sources.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sources.length == 1 ? '1 source' : '${sources.length} sources',
            style: text.labelMedium?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.xs),
          for (var i = 0; i < sources.length; i++)
            _SourceRow(index: i + 1, source: sources[i]),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final int index;
  final Citation source;

  const _SourceRow({required this.index, required this.source});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinTouchTarget),
      child: InkWell(
        onTap: () => openUrl(source.url.toString()),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text('$index.',
                    style: text.bodySmall?.copyWith(color: c.textFaint)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title.isEmpty ? source.url.host : source.title,
                      style: text.bodySmall?.copyWith(color: c.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // The host, not the whole URL: it is what tells somebody
                    // whether to trust the row, and a full URL wraps to three
                    // lines and says less.
                    Text(source.url.host,
                        style: text.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chip while a search is running.
///
/// Anthropic reports the tool starting and finishing, so this is observed
/// rather than assumed. Gemini does not, and gets no chip — a synthetic one
/// would be claiming to have seen something that was never reported.
class SearchingChip extends StatelessWidget {
  const SearchingChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.textMuted),
          ),
          const SizedBox(width: Space.sm),
          Text('Searching the web…',
              style: text.bodySmall?.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}
