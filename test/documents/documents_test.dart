import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift/documents/documents.dart';
import 'package:shift/documents/docx.dart';
import 'package:shift/documents/markdown_blocks.dart';
import 'package:shift/documents/pptx.dart';
import 'package:shift/documents/xlsx.dart';

/// The document writers.
///
/// **What these assert and what they cannot.** They read the package back and
/// check its parts, which catches a missing relationship, a dropped block and
/// bad escaping. They cannot tell you Word opens the file — nothing in Dart
/// can. That is `tool/gen_docs.dart` plus a reader that is not ours, and the
/// one bug this suite would have missed was found exactly that way: a
/// `docProps/core.xml` nothing pointed at, so every document was called "Word
/// Document" and every part of it was correct.
void main() {
  /// The named part, as text.
  String part(List<int> bytes, String path) {
    final file = ZipDecoder()
        .decodeBytes(bytes)
        .files
        .firstWhere((f) => f.name == path, orElse: () => ArchiveFile('', 0, []));
    expect(file.name, path, reason: 'the package has no $path');
    return utf8.decode(file.content as List<int>);
  }

  List<String> names(List<int> bytes) =>
      ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();

  group('blocks', () {
    test('each shape is recognised', () {
      final blocks = parseBlocks('''
# Title

Some prose that is
hard wrapped.

- one
- two

1. first
2. second

> quoted

```
code line
```
''');
      expect(blocks.map((b) => b.kind), [
        BlockKind.heading1,
        BlockKind.paragraph,
        BlockKind.bullet,
        BlockKind.bullet,
        BlockKind.number,
        BlockKind.number,
        BlockKind.quote,
        BlockKind.code,
      ]);
      // A hard-wrapped paragraph is one paragraph. Honouring the wrap would put
      // a line break in the middle of every sentence.
      expect(blocks[1].text, 'Some prose that is hard wrapped.');
    });

    test('emphasis becomes runs, and a snake_case word survives', () {
      final runs = parseRuns('a **bold** and *italic* and read_the_file now');
      expect(runs.where((r) => r.bold).map((r) => r.text), ['bold']);
      expect(runs.where((r) => r.italic).map((r) => r.text), ['italic']);
      // The underscores are part of the identifier. Treated as emphasis, the
      // word comes out as `readthefile`, which is a silent corruption.
      expect(runs.map((r) => r.text).join(), contains('read_the_file'));
    });

    test('an unterminated fence still yields its code', () {
      // Withholding is a presentation choice, never a deletion — the same rule
      // the chat surface's fence filter follows.
      final blocks = parseBlocks('```\nkept\n');
      expect(blocks.single.kind, BlockKind.code);
      expect(blocks.single.text, 'kept');
    });
  });

  group('docx', () {
    test('every part it declares is in the package', () {
      final bytes = buildDocx('# Hi');
      final types = part(bytes, '[Content_Types].xml');

      for (final path in [
        'word/document.xml',
        'word/styles.xml',
        'word/numbering.xml',
        'docProps/core.xml',
      ]) {
        expect(names(bytes), contains(path));
        expect(types, contains(path), reason: '$path is not declared');
      }
    });

    test('the core properties are related, not merely present', () {
      // The bug this exists for: the part was written and correct, nothing
      // pointed at it, and every document was called "Word Document".
      expect(part(buildDocx('# Q3 Brief'), '_rels/.rels'),
          contains('docProps/core.xml'));
    });

    test('headings, lists and emphasis reach the document', () {
      final xml = part(buildDocx('# Title\n\n- one\n\n1. first\n\n**bold**'),
          'word/document.xml');

      expect(xml, contains('w:val="Heading1"'));
      expect(xml, contains('w:val="ListBullet"'));
      expect(xml, contains('w:val="ListNumber"'));
      // A list style with no numbering definition indents the text and draws
      // no bullet — a list until you press Enter.
      expect(xml, contains('<w:numId w:val="1"/>'));
      expect(xml, contains('<w:numId w:val="2"/>'));
      expect(xml, contains('<w:b/>'));
    });

    test('the title is the first heading when nobody named it', () {
      expect(part(buildDocx('# Q3 Brief\n\nText.'), 'docProps/core.xml'),
          contains('Q3 Brief'));
    });

    test('markup in the text is escaped, not emitted', () {
      final xml = part(buildDocx("Dave's <b>notes</b> & more"),
          'word/document.xml');
      expect(xml, contains('&lt;b&gt;'));
      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('<b>notes')));
    });

    test('an empty document is still a document', () {
      // `<w:body/>` opens as damaged rather than as a blank page, which is a
      // confusing way to say there was nothing to write.
      expect(part(buildDocx(''), 'word/document.xml'), contains('<w:p/>'));
    });

    test('a control character is dropped rather than written', () {
      // Word does not report a bad character. It reports the file as corrupt.
      expect(part(buildDocx('beforeafter'), 'word/document.xml'),
          contains('beforeafter'));
    });
  });

  group('xlsx', () {
    test('quoted fields survive commas, quotes and blank cells', () {
      final rows = parseCsv('a,"b,c","say ""hi""",\nd,e,f,g\n');
      expect(rows.first, ['a', 'b,c', 'say "hi"', '']);
      expect(rows.last, ['d', 'e', 'f', 'g']);
      expect(rows, hasLength(2), reason: 'a trailing newline is not a row');
    });

    test('numbers are numbers and text is text', () {
      final xml = part(buildXlsx('Name,Count\nBerlin,124000\n'),
          'xl/worksheets/sheet1.xml');
      // The whole reason to want a spreadsheet: a column of text sums to zero
      // and looks identical until somebody tries.
      expect(xml, contains('<v>124000</v>'));
      expect(xml, contains('t="inlineStr"'));
    });

    test('a header row is bolded and frozen, a row of numbers is not', () {
      expect(part(buildXlsx('Name,Count\nBerlin,124000\n'),
              'xl/worksheets/sheet1.xml'),
          contains('state="frozen"'));
      // No header here: bolding it would assert something about the data that
      // is not true.
      expect(part(buildXlsx('2025,14\n2026,18\n'), 'xl/worksheets/sheet1.xml'),
          isNot(contains('state="frozen"')));
    });

    test('cell references count past Z', () {
      expect(cellRef(0, 0), 'A1');
      expect(cellRef(25, 6), 'Z7');
      expect(cellRef(26, 0), 'AA1');
      expect(cellRef(27, 0), 'AB1');
    });

    test('a sheet name Excel would refuse is repaired', () {
      // Excel does not report an invalid name — it reports the workbook as
      // unreadable.
      final xml = part(
          buildXlsx('a,b\n1,2\n', sheetName: 'Q3/Q4 [draft]: numbers ' * 3),
          'xl/workbook.xml');
      final name = RegExp('name="([^"]*)"').firstMatch(xml)!.group(1)!;
      expect(name.length, lessThanOrEqualTo(31));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('[')));
    });
  });

  group('pptx', () {
    test('a heading starts a slide, and a rule does too', () {
      final slides = parseSlides('# One\n\n- a\n\n## Two\n\ntext\n\n---\n\n# Three');
      expect(slides.map((s) => s.title), ['One', 'Two', 'Three']);
      expect(slides[1].lines, ['text']);
    });

    test('prose under a heading is kept, not only bullets', () {
      // A model writes a sentence of context under a heading, and dropping it
      // loses the point of the slide.
      expect(parseSlides('# One\n\nThe context.\n\n- a').single.lines,
          ['The context.', 'a']);
    });

    test('emphasis is flattened rather than shown', () {
      expect(parseSlides('# T\n\n- **bold** point').single.lines,
          ['bold point']);
    });

    test('nothing at all still makes one slide', () {
      // A presentation with no slides is not a smaller presentation.
      expect(parseSlides('').single.title, 'Untitled');
      expect(names(buildPptx('')), contains('ppt/slides/slide1.xml'));
    });

    test('every slide is declared, related and present', () {
      final bytes = buildPptx('# One\n\n# Two\n\n# Three');
      final types = part(bytes, '[Content_Types].xml');
      final rels = part(bytes, 'ppt/_rels/presentation.xml.rels');

      for (var i = 1; i <= 3; i++) {
        expect(names(bytes), contains('ppt/slides/slide$i.xml'));
        expect(types, contains('/ppt/slides/slide$i.xml'));
        expect(rels, contains('slides/slide$i.xml'));
      }
    });
  });

  group('choosing the format', () {
    test('the extension decides, and case does not matter', () {
      expect(buildDocument('a/b/report.DOCX', '# Hi'), isNotNull);
      expect(buildDocument('sheet.xlsx', 'a,b\n1,2\n'), isNotNull);
      expect(buildDocument('deck.pptx', '# Hi'), isNotNull);
    });

    test('a format it cannot write is null, not a mislabelled file', () {
      // The alternative is a `.pdf` full of WordprocessingML, which is the one
      // outcome worse than saying no.
      for (final path in ['report.pdf', 'notes.md', 'nodots', '.hidden']) {
        expect(buildDocument(path, 'x'), isNull, reason: path);
      }
    });

    test('the sheet is named after the file', () {
      // `Sheet1` on a workbook called regions.xlsx reads as an untouched
      // default.
      expect(part(buildDocument('regions.xlsx', 'a,b\n1,2\n')!, 'xl/workbook.xml'),
          contains('name="Regions"'));
    });
  });
}
