import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/studio_result.dart';

/// Builds a real, openable `.pptx` (OOXML presentation) from a [DeckResult].
///
/// A .pptx is a ZIP of XML parts. This assembles a minimal-but-valid package: a
/// theme, one slide master + layout, and one slide per [DeckSlide] with a title
/// shape and a bulleted body shape. Pure — no I/O — so it is unit-testable by
/// decoding the returned bytes.
class DeckPptx {
  DeckPptx._();

  // 16:9 slide, in EMUs (914400 per inch).
  static const _cx = 12192000;
  static const _cy = 6858000;

  static Uint8List build(DeckResult deck) {
    final archive = Archive();
    void add(String path, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final slideCount = deck.slides.length;

    add('[Content_Types].xml', _contentTypes(slideCount));
    add('_rels/.rels', _rootRels);
    add('docProps/core.xml', _core(deck.title));
    add('docProps/app.xml', _app(deck.title, slideCount));
    add('ppt/presentation.xml', _presentation(slideCount));
    add('ppt/_rels/presentation.xml.rels', _presentationRels(slideCount));
    add('ppt/presProps.xml', _presProps);
    add('ppt/theme/theme1.xml', _theme);
    add('ppt/slideMasters/slideMaster1.xml', _slideMaster);
    add('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRels);
    add('ppt/slideLayouts/slideLayout1.xml', _slideLayout);
    add('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRels);
    for (var i = 0; i < slideCount; i++) {
      add('ppt/slides/slide${i + 1}.xml', _slide(deck.slides[i]));
      add('ppt/slides/_rels/slide${i + 1}.xml.rels', _slideRels);
    }

    final zip = ZipEncoder().encode(archive) ?? const <int>[];
    return Uint8List.fromList(zip);
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _contentTypes(int slideCount) {
    final slideOverrides = [
      for (var i = 1; i <= slideCount; i++)
        '<Override PartName="/ppt/slides/slide$i.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '$slideOverrides'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
  }

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  static String _core(String title) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(title)}</dc:title><dc:creator>SHIFT AI</dc:creator>'
      '<cp:lastModifiedBy>SHIFT AI</cp:lastModifiedBy></cp:coreProperties>';

  static String _app(String title, int slideCount) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>SHIFT AI</Application><Slides>$slideCount</Slides>'
      '<Company>SHIFT AI</Company></Properties>';

  static String _presentation(int slideCount) {
    final sldIds = [
      for (var i = 0; i < slideCount; i++)
        '<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>'
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$sldIds</p:sldIdLst>'
        '<p:sldSz cx="$_cx" cy="$_cy" type="screen16x9"/>'
        '<p:notesSz cx="$_cy" cy="$_cx"/></p:presentation>';
  }

  static String _presentationRels(int slideCount) {
    final slideRels = [
      for (var i = 0; i < slideCount; i++)
        '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>'
    ].join();
    final n = slideCount + 2;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '$slideRels'
        '<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
        '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>'
        '</Relationships>';
  }

  static const _presProps =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>';

  /// A slide: a title shape and a body shape holding the bullets.
  static String _slide(DeckSlide slide) {
    final bullets = slide.bullets.isEmpty
        ? '<a:p><a:endParaRPr lang="en-US"/></a:p>'
        : slide.bullets
            .map((b) =>
                '<a:p><a:pPr><a:buChar char="•"/></a:pPr>'
                '<a:r><a:rPr lang="en-US" sz="2000"/><a:t>${_esc(b)}</a:t></a:r></a:p>')
            .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        // Title
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="685800" y="457200"/>'
        '<a:ext cx="10820400" cy="1143000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:rPr lang="en-US" sz="4000" b="1"/>'
        '<a:t>${_esc(slide.title)}</a:t></a:r></a:p></p:txBody></p:sp>'
        // Body
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="685800" y="1828800"/>'
        '<a:ext cx="10820400" cy="4351338"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>$bullets</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:overrideClrMapping '
        'bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
        'accent2="accent2" accent3="accent3" accent4="accent4" '
        'accent5="accent5" accent6="accent6" hlink="hlink" '
        'folHlink="folHlink"/></p:clrMapOvr></p:sld>';
  }

  static const _slideRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
      '</Relationships>';

  static const _slideMaster =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
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

  static const _slideMasterRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
      '</Relationships>';

  static const _slideLayout =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
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

  static const _slideLayoutRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
      '</Relationships>';

  static const _theme =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="SHIFT AI">'
      '<a:themeElements><a:clrScheme name="SHIFT AI">'
      '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
      '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
      '<a:dk2><a:srgbClr val="1D1D1F"/></a:dk2><a:lt2><a:srgbClr val="F5F4EF"/></a:lt2>'
      '<a:accent1><a:srgbClr val="AF52DE"/></a:accent1>'
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
}
