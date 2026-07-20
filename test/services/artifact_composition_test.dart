import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/services/artifact_composition.dart';

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

  group('wantsCodeAndImageStudios', () {
    final noArtifacts = _withArtifacts(const []);
    final withArtifact = _withArtifacts([_htmlArtifact()]);

    test('a fresh page request that also wants photos wants both studios',
        () {
      expect(
        wantsCodeAndImageStudios(
            noArtifacts, 'build me a dog treat website with several photos'),
        isTrue,
      );
    });

    test('a plain page request without any visual keyword wants only code',
        () {
      expect(
        wantsCodeAndImageStudios(
            noArtifacts, 'build me a landing page for my bakery'),
        isFalse,
      );
    });

    test('a standalone image request without a page keyword wants only '
        'image', () {
      expect(wantsCodeAndImageStudios(noArtifacts, 'make me a logo'), isFalse);
    });

    test('a non-page, non-image request wants neither', () {
      expect(
        wantsCodeAndImageStudios(noArtifacts, 'write a python function'),
        isFalse,
      );
    });

    test('stays false once an HTML artifact already exists — that\'s an '
        'edit, handled by findArtifactCompositionTarget instead', () {
      expect(
        wantsCodeAndImageStudios(
            withArtifact, 'build me a dog treat website with several photos'),
        isFalse,
      );
    });

    test('stays false for "add a hero image to the website" even with no '
        'artifact yet — the wording refers to an existing site, not a new '
        'build', () {
      expect(
        wantsCodeAndImageStudios(noArtifacts, 'add a hero image to the website'),
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
}
