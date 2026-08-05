import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/artifacts/preview_document.dart';

const _page = '''
<!DOCTYPE html>
<html><head><title>Coffee</title></head>
<body><a href="/menu">Menu</a><img src="https://example.test/hero.jpg"></body>
</html>
''';

void main() {
  group('previewDocument', () {
    test('sends links to a new tab instead of over the preview', () {
      // The reported behaviour: clicking a button in a generated page "does
      // some weird stuff". A `srcdoc` frame resolves `/menu` against the app's
      // own address, so the click replaced the preview with the hosting's 404
      // — the page apparently destroying itself.
      expect(previewDocument(_page), contains('<base target="_blank">'));
    });

    test('leaves a page that chose its own base alone', () {
      // A page that sets `<base>` has made a deliberate decision about how its
      // links resolve. Overriding it would break the pages written most
      // carefully.
      const chosen = '<html><head><base href="https://example.test/"></head>'
          '<body>x</body></html>';

      expect(previewDocument(chosen), isNot(contains('target="_blank"')));
    });

    test('labels an image that does not load', () {
      // "It does not present me with an image even it acts like it does" — the
      // layout reserves the space and nothing arrives. A gap that pretends is
      // worse than one that explains.
      final prepared = previewDocument(_page);

      expect(prepared, contains('Image unavailable'));
      expect(prepared, contains("tagName === 'IMG'"));
    });

    test('listens in the capture phase, because error does not bubble', () {
      // The whole fallback is inert without this, and it would be inert
      // silently — every image would look exactly as broken as before.
      expect(previewDocument(_page), contains('true); // capture'));
    });

    test('keeps the page itself untouched', () {
      final prepared = previewDocument(_page);

      expect(prepared, contains('<title>Coffee</title>'));
      expect(prepared, contains('href="/menu"'));
      expect(prepared, contains('https://example.test/hero.jpg'),
          reason: 'the download must be the file the model wrote');
    });

    test('is not applied twice', () {
      final once = previewDocument(_page);

      expect(previewDocument(once), once);
    });

    test('handles a fragment with no head', () {
      final prepared = previewDocument('<div>just a fragment</div>');

      expect(prepared, contains('just a fragment'));
      expect(prepared, contains('<base target="_blank">'));
    });
  });
}
