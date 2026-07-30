import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/turn/request_title.dart';

void main() {
  const request = 'build me a landing page for my bakery';

  group('a page names itself', () {
    test('its <title> beats the request', () {
      // The request names the errand, not the deliverable — and two pages for
      // the same bakery would get near-identical names from it.
      expect(
        titleFromArtifact(
          '<!DOCTYPE html><html><head><title>Rye &amp; Co.</title></head>'
          '<body><h1>Rye</h1></body></html>',
          request: request,
        ),
        'Rye &amp; Co.',
      );
    });

    test('its headline is the next best thing', () {
      expect(
        titleFromArtifact(
          '<html><body><h1><span>Morning Loaf</span></h1></body></html>',
          request: request,
        ),
        'Morning Loaf',
      );
    });

    test('template boilerplate is worse than the request', () {
      for (final junk in ['Document', 'Untitled', 'index', 'My Website']) {
        expect(
          titleFromArtifact('<html><head><title>$junk</title></head>'
              '<body></body></html>', request: request),
          'Landing page for my bakery',
          reason: junk,
        );
      }
    });
  });

  group('code names itself', () {
    test('by what it declares', () {
      expect(
        titleFromArtifact(
          'export default function PricingTable() {\n  return null;\n}',
          language: 'jsx',
          request: 'build me a pricing table',
        ),
        'Pricing Table (jsx)',
      );
    });

    test('snake_case reads as words too', () {
      expect(
        titleFromArtifact('def fetch_orders(client):\n    pass',
            language: 'python', request: 'write me a script'),
        'Fetch orders (python)',
      );
    });

    test('a name that says nothing falls back', () {
      // `main`, `app`, `index` are what every file is called.
      expect(
        titleFromArtifact('function main() {\n  run();\n}',
            language: 'js', request: 'build me a dashboard app'),
        'Dashboard app',
      );
    });
  });

  test('with nothing to read it is still the old rule', () {
    expect(titleFromArtifact('just some text', request: request),
        'Landing page for my bakery');
  });
}
