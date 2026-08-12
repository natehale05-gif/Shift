/// Markdown, reduced to the blocks a document is made of.
///
/// Not a Markdown renderer — the chat surface already has one of those, and it
/// produces widgets. This produces *structure*, because a `.docx` needs to know
/// that a line is a heading rather than that it should be drawn larger. The two
/// jobs look alike and share nothing.
///
/// Deliberately a small subset: headings, paragraphs, bullets, numbered items,
/// quotes and code. That is what a model writes when asked for a report, and
/// every construct beyond it (tables, footnotes, images) is one that would need
/// a matching OOXML part and would be wrong in a way nobody notices until Word
/// refuses to open the file. Anything unrecognised is a paragraph, which is the
/// failure that loses formatting rather than content.
library;

enum BlockKind { heading1, heading2, heading3, paragraph, bullet, number, quote, code }

/// One block, and the inline runs inside it.
class Block {
  final BlockKind kind;
  final List<Run> runs;

  const Block(this.kind, this.runs);

  /// The block's text with its formatting dropped. Handy for a title, and for
  /// tests that care what it says rather than how.
  String get text => runs.map((r) => r.text).join();

  bool get isEmpty => text.trim().isEmpty;
}

/// A stretch of text with one set of emphasis.
class Run {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  const Run(this.text, {this.bold = false, this.italic = false, this.code = false});
}

/// Splits [markdown] into blocks.
///
/// Blank-line separated, except for lists and code fences, which run until the
/// list or the fence ends. A paragraph split across several source lines is
/// joined with spaces — hard-wrapped Markdown is normal, and honouring the
/// wrap would put a line break in the middle of every sentence.
List<Block> parseBlocks(String markdown) {
  final out = <Block>[];
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    final joined = paragraph.join(' ').trim();
    paragraph.clear();
    if (joined.isNotEmpty) out.add(Block(BlockKind.paragraph, parseRuns(joined)));
  }

  var inCode = false;
  final code = <String>[];

  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        out.add(Block(BlockKind.code, [Run(code.join('\n'), code: true)]));
        code.clear();
        inCode = false;
      } else {
        flush();
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      code.add(line);
      continue;
    }

    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      flush();
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flush();
      final level = heading.group(1)!.length;
      out.add(Block(
        // Beyond three, everything is a heading 3. Word has nine levels and
        // nobody reading a two-page brief can tell the fourth from the fifth.
        level == 1
            ? BlockKind.heading1
            : level == 2
                ? BlockKind.heading2
                : BlockKind.heading3,
        parseRuns(heading.group(2)!.trim()),
      ));
      continue;
    }

    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flush();
      out.add(Block(BlockKind.bullet, parseRuns(bullet.group(1)!)));
      continue;
    }

    final numbered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      flush();
      out.add(Block(BlockKind.number, parseRuns(numbered.group(1)!)));
      continue;
    }

    if (trimmed.startsWith('>')) {
      flush();
      out.add(Block(BlockKind.quote, parseRuns(trimmed.substring(1).trim())));
      continue;
    }

    // A horizontal rule is a separator, not content. Kept out rather than
    // becoming a paragraph of dashes.
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      flush();
      continue;
    }

    paragraph.add(trimmed);
  }

  flush();
  // An unterminated fence still yields its code rather than swallowing it —
  // the same rule the chat surface's fence filter follows, for the same
  // reason: withholding is a presentation choice, never a deletion.
  //
  // Trailing blank lines go, because here they are the end of the *document*
  // rather than part of the code. Inside a closed fence they are kept: there
  // the writer put them between the code and the closing backticks.
  while (code.isNotEmpty && code.last.trim().isEmpty) {
    code.removeLast();
  }
  if (code.isNotEmpty) {
    out.add(Block(BlockKind.code, [Run(code.join('\n'), code: true)]));
  }
  return out;
}

/// Splits one line into emphasised runs.
///
/// `**bold**`, `*italic*`/`_italic_` and `` `code` ``. Scanned once, left to
/// right, rather than by nested regex: a regex pass per style would let
/// `**a `b` c**` come out with the code span outside the bold.
List<Run> parseRuns(String line) {
  final out = <Run>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;

  void emit({bool asCode = false, String? text}) {
    final value = text ?? buffer.toString();
    if (text == null) buffer.clear();
    if (value.isEmpty) return;
    out.add(Run(value, bold: bold, italic: italic, code: asCode));
  }

  var i = 0;
  while (i < line.length) {
    final rest = line.substring(i);
    if (rest.startsWith('**')) {
      emit();
      bold = !bold;
      i += 2;
      continue;
    }
    if (rest.startsWith('`')) {
      final end = line.indexOf('`', i + 1);
      if (end > i) {
        emit();
        emit(asCode: true, text: line.substring(i + 1, end));
        i = end + 1;
        continue;
      }
    }
    final char = line[i];
    if (char == '*' || char == '_') {
      // Only when it opens or closes a word, so `snake_case_names` survives.
      final before = i == 0 ? ' ' : line[i - 1];
      final after = i + 1 < line.length ? line[i + 1] : ' ';
      final boundary = italic ? after.trim().isEmpty || _punctuation(after)
                              : before.trim().isEmpty;
      if (boundary) {
        emit();
        italic = !italic;
        i += 1;
        continue;
      }
    }
    buffer.write(char);
    i += 1;
  }
  emit();
  return out.isEmpty ? const [Run('')] : out;
}

bool _punctuation(String c) => '.,;:!?)]}"\''.contains(c);
