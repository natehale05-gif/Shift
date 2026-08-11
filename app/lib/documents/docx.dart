import 'dart:typed_data';

import 'markdown_blocks.dart';
import 'ooxml.dart';

/// A real Word document, from Markdown.
///
/// **The model writes Markdown and the app builds the container.** That split
/// is the whole design. Asking a model to emit WordprocessingML would produce
/// something long, expensive and wrong in ways nobody sees until Word refuses
/// the file; asking it for Markdown asks for the thing it is best at, and the
/// XML below is deterministic and testable.
///
/// A minimal-but-valid package: content types, the package relationship, the
/// document part, and a styles part so headings are real Word headings rather
/// than large text. That last one matters more than it looks — a heading Word
/// *knows* is a heading is what makes a navigation pane, a table of contents
/// and an outline work, and it is the difference between a document somebody
/// can edit and a document they have to redo.
Uint8List buildDocx(String markdown, {String? title}) {
  final blocks = parseBlocks(markdown);
  final package = OoxmlPackage()
    ..addXml('[Content_Types].xml', _contentTypes)
    ..addXml(
        '_rels/.rels',
        rootRels(
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
          'word/document.xml',
        ))
    ..addXml('word/_rels/document.xml.rels', _documentRels)
    ..addXml('word/styles.xml', _styles)
    ..addXml('word/numbering.xml', _numbering)
    ..addXml('docProps/core.xml', _core(title ?? _titleOf(blocks)))
    ..addXml('word/document.xml', _document(blocks));

  return package.encode();
}

/// The document's own first heading, when the caller did not name it.
///
/// Falling back to the filename would be worse than falling back to nothing:
/// `q3-brief.docx` in the title bar of a document headed "Q3 Brief" reads as
/// the app having failed to notice.
String _titleOf(List<Block> blocks) {
  for (final block in blocks) {
    if (block.kind == BlockKind.heading1 && !block.isEmpty) return block.text;
  }
  return 'Document';
}

const _contentTypes = '$xmlHeader'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const _documentRels = '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
    '</Relationships>';

String _core(String title) => '$xmlHeader'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>${xmlEscape(title)}</dc:title>'
    '</cp:coreProperties>';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _document(List<Block> blocks) {
  final body = blocks.where((b) => !b.isEmpty).map(_paragraph).join();
  return '$xmlHeader'
      '<w:document xmlns:w="$_w"><w:body>'
      // An empty document still gets one empty paragraph. A `<w:body/>` with
      // nothing in it opens as a damaged file in Word rather than as a blank
      // page, which is a confusing way to say "there was nothing to write".
      '${body.isEmpty ? '<w:p/>' : body}'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
      '</w:sectPr>'
      '</w:body></w:document>';
}

String _paragraph(Block block) {
  final style = switch (block.kind) {
    BlockKind.heading1 => 'Heading1',
    BlockKind.heading2 => 'Heading2',
    BlockKind.heading3 => 'Heading3',
    BlockKind.quote => 'Quote',
    BlockKind.code => 'Code',
    BlockKind.bullet => 'ListBullet',
    BlockKind.number => 'ListNumber',
    BlockKind.paragraph => 'Normal',
  };

  final runs = block.kind == BlockKind.code
      // Code keeps its line breaks. Joined into one run they would come out as
      // a single line, which is the one thing a code block must not do.
      ? block.text
          .split('\n')
          .map((line) => _run(Run(line, code: true)))
          .join('<w:r><w:br/></w:r>')
      : block.runs.map(_run).join();

  // A list paragraph names its numbering definition. Without it the style
  // indents the text and draws no bullet at all — which looks like a list
  // until you press Enter, and then it is not one. This is the difference
  // between a document somebody can edit and one they have to redo.
  final numbering = switch (block.kind) {
    BlockKind.bullet => '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>',
    BlockKind.number => '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr>',
    _ => '',
  };

  return '<w:p><w:pPr><w:pStyle w:val="$style"/>$numbering</w:pPr>$runs</w:p>';
}

String _run(Run run) {
  final properties = [
    if (run.bold) '<w:b/>',
    if (run.italic) '<w:i/>',
    if (run.code) '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>',
  ].join();

  return '<w:r>'
      '${properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>'}'
      // `xml:space="preserve"` or Word eats the space between two runs, so
      // **bold** followed by a word arrives as **bold**word.
      '<w:t xml:space="preserve">${xmlEscape(run.text)}</w:t>'
      '</w:r>';
}

/// Real Word styles, so the outline is real.
///
/// Each heading declares `w:outlineLvl`, which is what puts it in the
/// navigation pane and in a generated table of contents. Sizes are in
/// half-points, because that is what `w:sz` counts.
const _styles = '$xmlHeader'
    '<w:styles xmlns:w="$_w">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/>'
    '</w:rPr></w:rPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:styleId="Normal" w:default="1">'
    '<w:name w:val="Normal"/>'
    '<w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="0"/>'
    '<w:spacing w:before="240" w:after="120"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="1"/>'
    '<w:spacing w:before="200" w:after="100"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="2"/>'
    '<w:spacing w:before="160" w:after="80"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/>'
    '<w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/>'
    '<w:spacing w:after="60"/></w:pPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListNumber"><w:name w:val="List Number"/>'
    '<w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/>'
    '<w:spacing w:after="60"/></w:pPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr>'
    '<w:rPr><w:i/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="HTML Preformatted"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="20"/></w:rPr>'
    '</w:style>'
    '</w:styles>';

/// One bullet list and one numbered list, which is all this subset needs.
///
/// `w:abstractNum` defines the shape; `w:num` is the instance a paragraph
/// points at. Two levels of indirection for two lists looks like ceremony and
/// is not optional — Word resolves `w:numId` through it and treats a missing
/// definition as a corrupt part rather than as an unstyled list.
const _numbering = '$xmlHeader'
    '<w:numbering xmlns:w="$_w">'
    '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/>'
    '<w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/></w:rPr>'
    '</w:lvl></w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
    '<w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/>'
    '<w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>'
    '</w:lvl></w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
    '</w:numbering>';
