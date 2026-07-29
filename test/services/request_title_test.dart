import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/platform/download_service.dart';
import 'package:shift_ai/turn/request_title.dart';

void main() {
  test('strips the build verb, the pronoun and the article', () {
    expect(titleFromRequest('build me a landing page for my bakery'),
        'Landing page for my bakery');
  });

  test('reduces stacked politeness', () {
    expect(titleFromRequest('please can you create a dashboard app'),
        'Dashboard app');
    expect(titleFromRequest('hey, could you make me a pricing page'),
        'Pricing page');
  });

  test('keeps casing after the first letter', () {
    // Acronyms and proper nouns must survive — only the first character is
    // touched.
    expect(titleFromRequest('build a landing page for a SaaS product'),
        contains('SaaS'));
    expect(titleFromRequest('write an iOS onboarding screen'),
        startsWith('IOS onboarding'));
  });

  test('drops trailing politeness and punctuation', () {
    expect(titleFromRequest('build me a contact form, please!'), 'Contact form');
  });

  test('an already-clean title survives unchanged', () {
    expect(titleFromRequest('Landing page for my bakery'),
        'Landing page for my bakery');
  });

  test('truncates on a word boundary within the length cap', () {
    final title = titleFromRequest(
        'build me a landing page for a small artisanal sourdough bakery in '
        'north london with online ordering');
    expect(title.length, lessThanOrEqualTo(60));
    expect(title.split(' ').length, lessThanOrEqualTo(8));
    // No mid-word truncation.
    expect(title, isNot(endsWith('-')));
  });

  test('the download filename keeps the subject', () {
    // The regression this wave exists for: slugify keeps six words, so the raw
    // prompt used to yield "build_me_a_landing_page" — the subject dropped.
    const prompt = 'build me a landing page for my bakery';
    expect(DownloadService.slugify(prompt), isNot(contains('bakery')));
    expect(DownloadService.slugify(titleFromRequest(prompt)),
        contains('bakery'));
  });

  test('two different requests yield two different filenames', () {
    final a = DownloadService.slugify(
        titleFromRequest('build me a landing page for my bakery'));
    final b = DownloadService.slugify(
        titleFromRequest('build me a landing page for a law firm'));
    expect(a, isNot(b));
  });

  test('empty or preamble-only input falls back', () {
    expect(titleFromRequest(''), 'Untitled page');
    expect(titleFromRequest('   '), 'Untitled page');
    expect(titleFromRequest('please build me a'), 'Untitled page');
    expect(titleFromRequest('', fallback: 'Untitled code'), 'Untitled code');
  });
}
