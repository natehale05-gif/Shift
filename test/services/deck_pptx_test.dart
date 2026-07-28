import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/features/studios/deck/deck_pptx.dart';

void main() {
  const deck = DeckResult(
    title: 'Quarterly Review',
    slides: [
      DeckSlide(title: 'Quarterly Review', bullets: ['A SHIFT AI presentation']),
      DeckSlide(title: 'Highlights', bullets: ['Revenue up', 'Costs down', 'Team grew']),
      DeckSlide(title: 'Next Steps', bullets: ['Ship v2', 'Hire two engineers']),
    ],
    live: true,
  );

  test('build() produces a decodable ZIP with the required OOXML parts', () {
    final bytes = DeckPptx.build(deck);
    expect(bytes, isNotEmpty);
    // A .pptx is a ZIP — decoding proves the container is well-formed.
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, containsAll([
      '[Content_Types].xml',
      '_rels/.rels',
      'ppt/presentation.xml',
      'ppt/_rels/presentation.xml.rels',
      'ppt/slideMasters/slideMaster1.xml',
      'ppt/slideLayouts/slideLayout1.xml',
      'ppt/theme/theme1.xml',
      'ppt/slides/slide1.xml',
      'ppt/slides/slide2.xml',
      'ppt/slides/slide3.xml',
      'ppt/slides/_rels/slide1.xml.rels',
    ]));
  });

  test('one slide part per DeckSlide, and the slide text is embedded', () {
    final bytes = DeckPptx.build(deck);
    final archive = ZipDecoder().decodeBytes(bytes);
    final slideFiles =
        archive.files.where((f) => RegExp(r'ppt/slides/slide\d+\.xml$').hasMatch(f.name));
    expect(slideFiles, hasLength(3));

    final slide2 = archive.files.firstWhere((f) => f.name == 'ppt/slides/slide2.xml');
    final xml = utf8.decode(slide2.content as List<int>);
    expect(xml, contains('Highlights'));
    expect(xml, contains('Revenue up'));
    expect(xml, contains('<p:ph type="title"/>'));
  });

  test('content types declares an override for every slide', () {
    final bytes = DeckPptx.build(deck);
    final archive = ZipDecoder().decodeBytes(bytes);
    final ct = utf8.decode(archive.files
        .firstWhere((f) => f.name == '[Content_Types].xml')
        .content as List<int>);
    for (var i = 1; i <= 3; i++) {
      expect(ct, contains('/ppt/slides/slide$i.xml'));
    }
  });

  test('XML special characters in slide text are escaped', () {
    const tricky = DeckResult(
      title: 'A & B <C>',
      slides: [DeckSlide(title: 'A & B <C>', bullets: ['x < y & "z"'])],
    );
    final archive = ZipDecoder().decodeBytes(DeckPptx.build(tricky));
    final xml = utf8.decode(archive.files
        .firstWhere((f) => f.name == 'ppt/slides/slide1.xml')
        .content as List<int>);
    expect(xml, contains('A &amp; B &lt;C&gt;'));
    expect(xml, isNot(contains('<C>')));
  });
}
