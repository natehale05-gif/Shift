import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/turn/extract_artifact.dart';

/// When a reply is a deliverable, and — the harder half — when it is not.
void main() {
  Artifact? extract(String reply, {String request = 'build me a page'}) =>
      extractArtifact(reply, conversationId: 'c1', request: request);

  const page = '''
<!DOCTYPE html>
<html>
<head><title>Bakery</title></head>
<body><h1>Fresh bread</h1></body>
</html>''';

  group('a deliverable', () {
    test('a whole document becomes an artifact', () {
      final made = extract('Here you go:\n```html\n$page\n```');
      expect(made, isNotNull);
      expect(made!.kind, ArtifactKind.html);
      expect(made.versions.single.content, contains('<h1>Fresh bread</h1>'));
    });

    test('a whole document wins even when prose outweighs it', () {
      // v1's F4: the router, shown only the current message, answered "chat"
      // for "give it to me as an artifact" and a finished page was left as a
      // fence in the transcript. Extraction stopped trusting the route.
      final chatter = 'I have written this out at length. ' * 40;
      final made = extract('$chatter\n```html\n$page\n```\n$chatter');
      expect(made, isNotNull);
    });

    test('it is named from the page, not the errand that asked for it', () {
      // "build me a landing page for my bakery" names the request; the page
      // calls itself "Bakery", and it chose that with the whole thing in view.
      final made = extract('```html\n$page\n```',
          request: 'build me a landing page for my bakery');
      expect(made!.title, 'Bakery');
    });

    test('two different requests produce two different titles', () {
      // v1's A4 regression: every live artifact was called "Generated page",
      // so a second download collided with the first.
      final a = extract('```python\ndef alpha():\n  return 1\n\n\nx = 1\n```',
          request: 'write alpha');
      final b = extract('```python\ndef beta():\n  return 2\n\n\ny = 2\n```',
          request: 'write beta');
      expect(a!.title, isNot(b!.title));
    });
  });

  group('not a deliverable', () {
    test('no fence at all', () {
      expect(extract('You centre it with flexbox.'), isNull);
    });

    test('a block too short to be a file', () {
      expect(extract('Try:\n```css\n.a { display: flex }\n```'), isNull);
    });

    test('a snippet inside a longer answer stays in the answer', () {
      // The cost of getting this wrong is real: pull a six-line snippet into a
      // side panel and the answer to "how do I centre a div" has been hidden
      // behind a tab.
      final prose = 'Flexbox is the usual approach and here is why. ' * 30;
      final made = extract('$prose\n```css\n.a {\n  display: flex;\n'
          '  align-items: center;\n  justify-content: center;\n}\n```\n$prose');
      expect(made, isNull);
    });

    test('the same block *is* one when it is the whole reply', () {
      final made = extract('```css\n.a {\n  display: flex;\n'
          '  align-items: center;\n  justify-content: center;\n}\n```');
      expect(made, isNotNull);
      expect(made!.kind, ArtifactKind.code);
      expect(made.language, 'css');
    });
  });

  group('what counts as a whole document', () {
    test('a doctype or a matched html pair', () {
      expect(isWholeDocument('<!DOCTYPE html><html></html>'), isTrue);
      expect(isWholeDocument('<html><body>x</body></html>'), isTrue);
    });

    test('a handful of tags is not a page', () {
      // Matching any HTML at all would turn every answer that mentions a
      // `<div>` into an artifact.
      expect(isWholeDocument('<div class="row"><span>hi</span></div>'), isFalse);
      expect(isWholeDocument('<html><body>unclosed'), isFalse);
    });
  });
}
