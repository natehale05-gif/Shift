import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../artifacts/mermaid_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../artifacts/iframe_view_stub.dart'
    if (dart.library.html) '../../artifacts/iframe_view_web.dart';

/// Renders assistant markdown. This is the only file that touches the
/// markdown package directly — if gpt_markdown ever needs replacing, the
/// swap happens here without disturbing the message layout.
class MarkdownMessage extends StatelessWidget {
  final String text;

  const MarkdownMessage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GptMarkdown(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      onLinkTap: (url, title) {},
      codeBuilder: (context, language, code, closed) =>
          language.toLowerCase() == 'mermaid'
              ? _MermaidBlock(code: code, closed: closed)
              : _CodeBlock(language: language, code: code),
      highlightBuilder: (context, inlineCode, style) =>
          _InlineCode(code: inlineCode),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String language;
  final String code;

  const _CodeBlock({required this.language, required this.code});

  @override
  Widget build(BuildContext context) {
    // Fixed dark chrome in both themes, matching the Code Studio artifact
    // card, so code always reads as a distinct material.
    const headerColor = Color(0xFF21252B);
    const bodyColor = Color(0xFF282C34);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bodyColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: headerColor,
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'code' : language,
                  style: const TextStyle(
                    color: Color(0xFF9DA5B4),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy code',
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  color: const Color(0xFF9DA5B4),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: code)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: HighlightView(
              code,
              language: language.isEmpty ? 'plaintext' : language,
              theme: atomOneDarkTheme,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a ```mermaid fence as a live diagram in a sandboxed iframe, using
/// the bundled mermaid runtime.
class _MermaidBlock extends StatelessWidget {
  final String code;

  /// Whether the ```mermaid fence has finished streaming. We only render once
  /// closed, so mermaid never parses a half-written diagram.
  final bool closed;

  const _MermaidBlock({required this.code, required this.closed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final dark = theme.brightness == Brightness.dark;
    if (!closed) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 10),
            Text('Drawing diagram…', style: theme.textTheme.labelMedium),
          ],
        ),
      );
    }
    return FutureBuilder<String>(
      future: MermaidService.buildHtml(code, dark: dark),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          height: 320,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: buildSandboxedIframe(
            viewKey: 'mermaid-${code.hashCode}-${dark ? 'd' : 'l'}',
            htmlContent: snapshot.data!,
          ),
        );
      },
    );
  }
}

class _InlineCode extends StatelessWidget {
  final String code;

  const _InlineCode({required this.code});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) - 2,
          color: theme.textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}
