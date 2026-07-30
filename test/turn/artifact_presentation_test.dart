import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/studio_detection.dart';

/// A whole page, as a model actually returns one.
const _wholePage = '''
Here you go — the complete site as a single self-contained artifact.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Roast & Co. — Online Coffee Shop</title>
</head>
<body>
<h1>Roast &amp; Co.</h1>
<p>Single-origin beans, roasted weekly.</p>
</body>
</html>
```
''';

/// A few tags quoted to explain something. Must stay in the conversation.
const _explanation = '''
You can centre it with flexbox:

```html
<div class="row">
  <span>left</span>
  <span>right</span>
</div>
```

Add `display: flex` to `.row` and it lines up.
''';

void main() {
  group('wantsArtifactPresentation', () {
    test('the phrasing that lost a finished page', () {
      // Verbatim from the report: Claude had just written the whole site,
      // the user asked for it as an artifact, and it came back as a code
      // fence in the chat bubble.
      expect(
          StudioDetection.wantsArtifactPresentation('give it to me as an artifact'),
          isTrue);
    });

    test('other ways of asking for the same thing', () {
      for (final input in [
        'make that an artifact',
        'put it in an artifact',
        'can you render it as an artifact',
        'show it in the side panel',
        'I want that as a downloadable file',
        'turn this into an artifact please',
        'give me that as a separate file',
      ]) {
        expect(StudioDetection.wantsArtifactPresentation(input), isTrue,
            reason: input);
      }
    });

    test('a question about artifacts is not a request for one', () {
      for (final input in [
        'what is an artifact?',
        'the artifact is broken',
        'why did the artifact disappear',
        'how do artifacts work',
      ]) {
        expect(StudioDetection.wantsArtifactPresentation(input), isFalse,
            reason: input);
      }
    });

    test('ordinary prompts are unaffected', () {
      for (final input in [
        'what is the capital of France',
        'write me a haiku about the ocean',
        'summarise this article',
      ]) {
        expect(StudioDetection.wantsArtifactPresentation(input), isFalse,
            reason: input);
      }
    });
  });

  group('keywordRoute', () {
    test('an explicit artifact request routes to code', () {
      // Without this the router model is asked to classify a follow-up it
      // cannot possibly read, having never seen the conversation.
      expect(keywordRoute('give it to me as an artifact'), ChatRoute.code);
      expect(keywordRoute('make that an artifact'), ChatRoute.code);
    });

    test('a plain question still routes to chat', () {
      expect(keywordRoute('what is the capital of France'), ChatRoute.chat);
    });
  });

  group('repliedWithWholeDocument', () {
    test('a complete page is a deliverable', () {
      expect(RealChatService.repliedWithWholeDocument(_wholePage), isTrue);
    });

    test('a page without a doctype still counts', () {
      expect(
          RealChatService.repliedWithWholeDocument(
              '```html\n<html><body><h1>Hi</h1></body></html>\n```'),
          isTrue);
    });

    test('a fragment quoted to explain something is not', () {
      // The line that keeps this from turning every answer mentioning a
      // <div> into an artifact.
      expect(RealChatService.repliedWithWholeDocument(_explanation), isFalse);
    });

    test('prose alone is not', () {
      expect(
          RealChatService.repliedWithWholeDocument(
              'HTML documents start with <!DOCTYPE html>.'),
          isFalse,
          reason: 'mentioned in prose, not fenced');
    });

    test('a non-HTML code block is not', () {
      expect(
          RealChatService.repliedWithWholeDocument(
              '```python\nprint("hello")\n```'),
          isFalse);
    });

    test('a whole page in a later block still counts', () {
      expect(
          RealChatService.repliedWithWholeDocument(
              '```sh\nnpm i\n```\nthen:\n```html\n<!DOCTYPE html>\n<html></html>\n```'),
          isTrue);
    });
  });

  group('extractCodeArtifact', () {
    test('pulls the page out of the reply', () {
      final artifact = RealChatService.extractCodeArtifact(_wholePage, 'c1',
          title: 'Coffee website');
      expect(artifact, isNotNull);
      expect(artifact!.kind.name, 'html');
      expect(artifact.title, 'Coffee website');
      expect(artifact.latest.content, contains('Roast &amp; Co.'));
      expect(artifact.latest.content, isNot(contains('```')),
          reason: 'the fence markers are not part of the page');
    });
  });
}
