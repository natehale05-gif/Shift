import 'dart:typed_data';

import 'markdown_blocks.dart';
import 'ooxml.dart';

/// A real presentation, from Markdown.
///
/// Ported from v1's `deck_pptx.dart` and reviewed line by line rather than
/// rewritten: the package layout — a theme, one master, one layout, one part
/// per slide, and the relationship graph tying them together — is a set of
/// facts about PowerPoint that a fresh attempt would rediscover as a file that
/// will not open. What is new here is the input: v1 took a structured
/// `DeckResult` from its own studio, and this takes what a model writes.
///
/// **A heading starts a slide.** `#` and `##` both do, and so does a `---`
/// rule, because those are the three ways a model separates slides when asked
/// for a deck. Everything under a heading becomes its body.
Uint8List buildPptx(String markdown, {String? title}) {
  final slides = parseSlides(markdown);
  final package = OoxmlPackage()
    ..addXml('[Content_Types].xml', _contentTypes(slides.length))
    ..addXml(
        '_rels/.rels',
        rootRels(
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
          'ppt/presentation.xml',
        ))
    ..addXml('docProps/core.xml', _core(title ?? slides.first.title))
    ..addXml('ppt/presentation.xml', _presentation(slides.length))
    ..addXml('ppt/_rels/presentation.xml.rels', _presentationRels(slides.length))
    ..addXml('ppt/presProps.xml', _presProps)
    ..addXml('ppt/theme/theme1.xml', _theme)
    ..addXml('ppt/slideMasters/slideMaster1.xml', _slideMaster)
    ..addXml('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRels)
    ..addXml('ppt/slideLayouts/slideLayout1.xml', _slideLayout)
    ..addXml('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRels);

  for (var i = 0; i < slides.length; i++) {
    package
      ..addXml('ppt/slides/slide${i + 1}.xml', _slide(slides[i]))
      ..addXml('ppt/slides/_rels/slide${i + 1}.xml.rels', _slideRels);
  }

  return package.encode();
}

/// One slide's worth of Markdown.
class Slide {
  final String title;
  final List<String> lines;

  const Slide(this.title, this.lines);
}

/// Splits [markdown] into slides.
///
/// Always returns at least one, because a presentation with no slides is not a
/// smaller presentation — PowerPoint reports it as damaged.
List<Slide> parseSlides(String markdown) {
  final slides = <Slide>[];
  String? title;
  var lines = <String>[];

  void close() {
    if (title == null && lines.isEmpty) return;
    slides.add(Slide(title ?? 'Untitled', lines));
    title = null;
    lines = <String>[];
  }

  for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(line)) {
      close();
      continue;
    }
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      if (level <= 2) {
        close();
        title = heading.group(2)!.trim();
      } else {
        // A deeper heading is a line on the slide it is under, not a slide of
        // its own. Otherwise a three-level outline becomes a deck of titles
        // with nothing on them.
        lines.add(heading.group(2)!.trim());
      }
      continue;
    }
    if (line.isEmpty) continue;

    final bullet = RegExp(r'^(?:[-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    // The prose is kept as well as the bullets. A model writes a sentence of
    // context under a heading, and dropping it would silently lose the point
    // of the slide.
    lines.add(_plain(bullet != null ? bullet.group(1)! : line));
  }
  close();

  return slides.isEmpty ? [const Slide('Untitled', [])] : slides;
}

/// Markdown emphasis removed.
///
/// A slide has no runs here — one size, one weight — so `**bold**` would arrive
/// with its asterisks showing, which is worse than losing the emphasis.
String _plain(String line) => parseRuns(line).map((r) => r.text).join();

// 16:9, in EMUs (914400 per inch).
const _cx = 12192000;
const _cy = 6858000;

String _contentTypes(int slideCount) {
  final slides = [
    for (var i = 1; i <= slideCount; i++)
      '<Override PartName="/ppt/slides/slide$i.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
  ].join();
  return '$xmlHeader'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
      '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
      '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
      '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
      '$slides'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '</Types>';
}

String _core(String title) => '$xmlHeader'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>${xmlEscape(title)}</dc:title>'
    '</cp:coreProperties>';

String _presentation(int slideCount) {
  final ids = [
    for (var i = 0; i < slideCount; i++)
      '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>'
  ].join();
  return '$xmlHeader'
      '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      '<p:sldIdLst>$ids</p:sldIdLst>'
      '<p:sldSz cx="$_cx" cy="$_cy" type="screen16x9"/>'
      '<p:notesSz cx="$_cy" cy="$_cx"/></p:presentation>';
}

String _presentationRels(int slideCount) {
  final slides = [
    for (var i = 0; i < slideCount; i++)
      '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>'
  ].join();
  final n = slideCount + 2;
  return '$xmlHeader'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
      '$slides'
      '<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
      '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>'
      '</Relationships>';
}

const _presProps = '$xmlHeader'
    '<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>';

String _slide(Slide slide) {
  final body = slide.lines.isEmpty
      ? '<a:p><a:endParaRPr lang="en-US"/></a:p>'
      : slide.lines
          .map((line) => '<a:p><a:pPr><a:buChar char="&#8226;"/></a:pPr>'
              '<a:r><a:rPr lang="en-US" sz="2000"/>'
              '<a:t>${xmlEscape(line)}</a:t></a:r></a:p>')
          .join();

  return '$xmlHeader'
      '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
      '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="685800" y="457200"/>'
      '<a:ext cx="10820400" cy="1143000"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr/><a:lstStyle/>'
      '<a:p><a:r><a:rPr lang="en-US" sz="4000" b="1"/>'
      '<a:t>${xmlEscape(slide.title)}</a:t></a:r></a:p></p:txBody></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
      '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
      '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="685800" y="1828800"/>'
      '<a:ext cx="10820400" cy="4351338"/></a:xfrm></p:spPr>'
      '<p:txBody><a:bodyPr/><a:lstStyle/>$body</p:txBody></p:sp>'
      '</p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping '
      'bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
      'accent2="accent2" accent3="accent3" accent4="accent4" '
      'accent5="accent5" accent6="accent6" hlink="hlink" '
      'folHlink="folHlink"/></p:clrMapOvr></p:sld>';
}

const _slideRels = '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    '</Relationships>';

const _slideMaster = '$xmlHeader'
    '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
    '<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
    '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>'
    '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
    'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
    'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
    '</p:sldMaster>';

const _slideMasterRels = '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
    '</Relationships>';

const _slideLayout = '$xmlHeader'
    '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'type="obj" preserve="1">'
    '<p:cSld name="Title and Content"><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>'
    '<p:clrMapOvr><a:overrideClrMapping bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" '
    'accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" '
    'accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:clrMapOvr>'
    '</p:sldLayout>';

const _slideLayoutRels = '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
    '</Relationships>';

/// The app's own palette, so a deck made here looks like it came from here.
const _theme = '$xmlHeader'
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="SHIFT AI">'
    '<a:themeElements><a:clrScheme name="SHIFT AI">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="1D1D1F"/></a:dk2><a:lt2><a:srgbClr val="F5F4EF"/></a:lt2>'
    '<a:accent1><a:srgbClr val="8B3FD6"/></a:accent1>'
    '<a:accent2><a:srgbClr val="007AFF"/></a:accent2>'
    '<a:accent3><a:srgbClr val="34C759"/></a:accent3>'
    '<a:accent4><a:srgbClr val="FF9500"/></a:accent4>'
    '<a:accent5><a:srgbClr val="FF2D55"/></a:accent5>'
    '<a:accent6><a:srgbClr val="5AC8FA"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
    '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>'
    '<a:fontScheme name="SHIFT AI"><a:majorFont><a:latin typeface="Georgia"/>'
    '<a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/>'
    '</a:minorFont></a:fontScheme>'
    '<a:fmtScheme name="SHIFT AI">'
    '<a:fillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
    '<a:lnStyleLst>'
    '<a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
    '<a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
    '<a:ln><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>';
