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
}
