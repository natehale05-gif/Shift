import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/features/artifacts/artifact_composition.dart';

Artifact _htmlArtifact({String content = '<!DOCTYPE html><html><body><h1>Hi</h1></body></html>'}) =>
    Artifact(
      id: 'art1',
      conversationId: 'c1',
      title: 'Bakery landing page',
      kind: ArtifactKind.html,
      versions: [ArtifactVersion(content: content, createdAt: DateTime(2026))],
    );

Conversation _withArtifacts(List<Artifact> artifacts) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      artifacts: artifacts,
    );

void main() {
  group('latestHtmlArtifact', () {
    test('returns null when there are no artifacts', () {
      expect(latestHtmlArtifact(_withArtifacts(const [])), isNull);
    });

    test('skips non-HTML artifacts to find the latest HTML one', () {
      final code = Artifact(
        id: 'code1',
        conversationId: 'c1',
        title: 'script.py',
        kind: ArtifactKind.code,
        versions: [ArtifactVersion(content: 'print(1)', createdAt: DateTime(2026))],
      );
      final html = _htmlArtifact();
      final found = latestHtmlArtifact(_withArtifacts([code, html]));
      expect(found?.id, 'art1');
    });
  });

  group('findArtifactCompositionTarget', () {
    test('finds the target when the prompt references both an image and '
        'the existing site', () {
      final convo = _withArtifacts([_htmlArtifact()]);
      final target =
          findArtifactCompositionTarget(convo, 'add a hero image to the website');
      expect(target?.id, 'art1');
    });

    test('stays null with no artifact in the conversation', () {
      final convo = _withArtifacts(const []);
      expect(
        findArtifactCompositionTarget(convo, 'add a hero image to the website'),
        isNull,
      );
    });

    test('stays null for a standalone image request unrelated to the site', () {
      final convo = _withArtifacts([_htmlArtifact()]);
      expect(
        findArtifactCompositionTarget(convo, 'make me a logo for a different brand'),
        isNull,
      );
    });

    test('stays null when the prompt has no visual-asset keyword at all', () {
      final convo = _withArtifacts([_htmlArtifact()]);
      expect(
        findArtifactCompositionTarget(convo, 'add a contact form to the website'),
        isNull,
      );
    });

    test('stays null for an audio/video request (image-only wrapper)', () {
      final convo = _withArtifacts([_htmlArtifact()]);
      expect(
          findArtifactCompositionTarget(
              convo, 'add background music to the website'),
          isNull);
      expect(
          findArtifactCompositionTarget(convo, 'add a video to the website'),
          isNull);
    });
  });

  group('findArtifactEdit', () {
    final convo = _withArtifacts([_htmlArtifact()]);

    test('classifies image / audio / video edits by keyword', () {
      expect(findArtifactEdit(convo, 'add a hero image to the website')?.kind,
          ArtifactMediaKind.image);
      expect(findArtifactEdit(convo, 'add background music to the website')?.kind,
          ArtifactMediaKind.audio);
      expect(findArtifactEdit(convo, 'add a soundtrack to my site')?.kind,
          ArtifactMediaKind.audio);
      expect(findArtifactEdit(convo, 'add a video to the website')?.kind,
          ArtifactMediaKind.video);
      expect(findArtifactEdit(convo, 'add a video clip to the page')?.kind,
          ArtifactMediaKind.video);
    });

    test('returns the target artifact', () {
      expect(findArtifactEdit(convo, 'add a video to the website')?.target.id,
          'art1');
    });

    test('image wins when several media words appear', () {
      // "background image" is an image reference even though "background" could
      // read as audio.
      expect(
          findArtifactEdit(convo, 'add a background image to the website')?.kind,
          ArtifactMediaKind.image);
    });

    test('stays null without an artifact-reference phrase', () {
      expect(findArtifactEdit(convo, 'make a separate music track'), isNull);
    });

    test('stays null with no artifact in the conversation', () {
      expect(
          findArtifactEdit(
              _withArtifacts(const []), 'add a video to the website'),
          isNull);
    });
  });

  group('embedImageAsHero', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    test('inserts the image right after the opening body tag', () {
      const html = '<!DOCTYPE html><html><body><h1>Hi</h1></body></html>';
      final result = embedImageAsHero(html, bytes, altText: 'A bakery hero shot');

      expect(result, contains('<body>'));
      final bodyIndex = result.indexOf('<body>');
      final imgIndex = result.indexOf('<img');
      final h1Index = result.indexOf('<h1>');
      expect(imgIndex, greaterThan(bodyIndex));
      expect(imgIndex, lessThan(h1Index));
      expect(result, contains('alt="A bakery hero shot"'));
      expect(result, contains('data:image/png;base64,${base64Encode(bytes)}'));
    });

    test('prepends the image when there is no body tag (a fragment)', () {
      const html = '<div>fragment</div>';
      final result = embedImageAsHero(html, bytes);
      expect(result.indexOf('<img'), lessThan(result.indexOf('<div>')));
    });

    test('escapes double quotes in alt text so the tag stays well-formed', () {
      const html = '<body></body>';
      final result = embedImageAsHero(html, bytes, altText: 'a "quoted" alt');
      expect(result, contains("a 'quoted' alt"));
    });
  });

  group('referencesExistingArtifact', () {
    test('true for "…to the website" / "…on the page" wording', () {
      expect(referencesExistingArtifact('add a hero image to the website'),
          isTrue);
      expect(referencesExistingArtifact('put a photo on the page'), isTrue);
    });

    test('false for a fresh build description', () {
      expect(
        referencesExistingArtifact(
            'build me a dog treat website with several photos'),
        isFalse,
      );
    });
  });

  group('photoCountHint', () {
    test('an explicit count wins', () {
      expect(photoCountHint('a website with 5 photos'), 5);
    });

    test('clamps an absurd explicit count', () {
      expect(photoCountHint('a website with 99 photos'), 6);
    });

    test('"several"/"multiple"/"many" default to a small gallery', () {
      expect(photoCountHint('a website with several photos'), 3);
      expect(photoCountHint('a website with multiple images'), 3);
    });

    test('"a few"/"couple" default to two', () {
      expect(photoCountHint('a website with a few photos'), 2);
      expect(photoCountHint('a website with a couple pictures'), 2);
    });

    test('a bare plural with no qualifier defaults to a small gallery', () {
      expect(photoCountHint('a website with photos'), 3);
    });

    test('a singular mention wants just one', () {
      expect(photoCountHint('a website with a logo'), 1);
      expect(photoCountHint('add a hero image'), 1);
    });
  });

  group('embedImageGallery', () {
    final images = [
      Uint8List.fromList([1, 2]),
      Uint8List.fromList([3, 4]),
      Uint8List.fromList([5, 6]),
    ];

    test('delegates to embedImageAsHero for a single image', () {
      const html = '<body><h1>Hi</h1></body>';
      final gallery = embedImageGallery(html, [images.first], altText: 'x');
      final hero = embedImageAsHero(html, images.first, altText: 'x');
      expect(gallery, hero);
    });

    test('embeds one <img> per photo for multiple images', () {
      const html = '<!DOCTYPE html><html><body><h1>Treats</h1></body></html>';
      final result = embedImageGallery(html, images, altText: 'Dog treats');
      expect('<img'.allMatches(result).length, images.length);
      for (final bytes in images) {
        expect(
          result,
          contains('data:image/png;base64,${base64Encode(bytes)}'),
        );
      }
    });

    test('inserts the gallery before existing body content', () {
      const html = '<body><h1>Treats</h1></body>';
      final result = embedImageGallery(html, images, altText: 'x');
      final bodyIndex = result.indexOf('<body>');
      final galleryIndex = result.indexOf('<div');
      final h1Index = result.indexOf('<h1>');
      expect(galleryIndex, greaterThan(bodyIndex));
      expect(galleryIndex, lessThan(h1Index));
    });
  });

  group('findRevisionTarget', () {
    Artifact codeArtifact() => Artifact(
          id: 'code1',
          conversationId: 'c1',
          title: 'script.py',
          kind: ArtifactKind.code,
          versions: [
            ArtifactVersion(content: 'print(1)', createdAt: DateTime(2026))
          ],
        );

    test('returns null when the conversation has no artifacts', () {
      expect(
        findRevisionTarget(_withArtifacts(const []), 'make the button red'),
        isNull,
      );
    });

    test('a new build request does not revise the existing page', () {
      // The regression this function exists for: demo mode used to overwrite
      // whatever artifact was last, so asking for a second page destroyed the
      // first one.
      final conversation = _withArtifacts([_htmlArtifact()]);
      expect(
        findRevisionTarget(conversation, 'build me a pricing page for a SaaS'),
        isNull,
      );
      expect(
        findRevisionTarget(conversation, 'create a dashboard app'),
        isNull,
      );
    });

    test('a change request revises the existing page', () {
      final conversation = _withArtifacts([_htmlArtifact()]);
      expect(
        findRevisionTarget(conversation, 'change the code so the button is red')
            ?.id,
        'art1',
      );
      expect(
        findRevisionTarget(conversation, 'make the heading bigger')?.id,
        'art1',
      );
    });

    test('a back-reference revises even alongside a build verb', () {
      final conversation = _withArtifacts([_htmlArtifact()]);
      expect(
        findRevisionTarget(conversation, 'build a contact form on the page')
            ?.id,
        'art1',
      );
    });

    test('skips interactive artifacts', () {
      // A recipe card is generated wholesale from its own prompt; a later code
      // request is never a revision of one.
      final recipe = Artifact(
        id: 'recipe1',
        conversationId: 'c1',
        title: 'Banana bread',
        kind: ArtifactKind.html,
        interactive: true,
        versions: [
          ArtifactVersion(content: '<html>card</html>', createdAt: DateTime(2026))
        ],
      );
      expect(
        findRevisionTarget(_withArtifacts([recipe]), 'make the heading bigger'),
        isNull,
      );
    });

    test('revises a code artifact too', () {
      expect(
        findRevisionTarget(_withArtifacts([codeArtifact()]), 'fix the off by one')
            ?.id,
        'code1',
      );
    });

    test('an unrelated prompt creates rather than revises', () {
      // Ambiguity resolves to create: a spare artifact is recoverable, an
      // overwritten one is not.
      expect(
        findRevisionTarget(_withArtifacts([_htmlArtifact()]), 'a poem about rain'),
        isNull,
      );
    });
  });
}
