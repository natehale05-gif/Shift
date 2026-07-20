import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/services/studio_composition.dart';

Artifact _htmlArtifact() => Artifact(
      id: 'art1',
      conversationId: 'c1',
      title: 'Bakery landing page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
          content: '<!DOCTYPE html><html><body><h1>Hi</h1></body></html>',
          createdAt: DateTime(2026),
        ),
      ],
    );

Conversation _convo({List<Artifact> artifacts = const []}) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      artifacts: artifacts,
    );

void main() {
  group('detectStudios', () {
    test('a bare page request names only Code', () {
      expect(detectStudios('build me a landing page for my bakery'),
          {StudioType.codeStudio});
    });

    test('names every studio a prompt explicitly mentions', () {
      final studios = detectStudios(
          'build a website with photos, a soundtrack, a voiceover, '
          'a video clip and a headline');
      expect(studios, {
        StudioType.codeStudio,
        StudioType.imageStudio,
        StudioType.musicStudio,
        StudioType.voiceAvatarStudio,
        StudioType.videoStudio,
        StudioType.copyScriptsStudio,
      });
    });

    test('a standalone media request names just that studio', () {
      expect(detectStudios('write and narrate a welcome message'),
          {StudioType.voiceAvatarStudio});
      expect(detectStudios('make me a logo'), {StudioType.imageStudio});
    });

    test('an empty-ish prompt names nothing', () {
      expect(detectStudios('hello there'), isEmpty);
    });
  });

  group('planComposition', () {
    test('an existing artifact + reference wording is an edit', () {
      final plan = planComposition(
        _convo(artifacts: [_htmlArtifact()]),
        'add a hero image to the website',
      );
      expect(plan.kind, CompositionKind.editArtifact);
      expect(plan.host, StudioType.imageStudio);
      expect(plan.editTarget?.id, 'art1');
    });

    test('a fresh page + photos request is a page assembly', () {
      final plan = planComposition(
        _convo(),
        'build me a dog treat website with several photos',
      );
      expect(plan.kind, CompositionKind.pageAssembly);
      expect(plan.host, StudioType.codeStudio);
      expect(plan.contributors, contains(StudioType.imageStudio));
    });

    test('a plain page request stays single-studio (none)', () {
      final plan =
          planComposition(_convo(), 'build me a landing page for my bakery');
      expect(plan.kind, CompositionKind.none);
    });

    test('a standalone image request stays single-studio (none)', () {
      final plan = planComposition(_convo(), 'make me a logo');
      expect(plan.kind, CompositionKind.none);
    });

    test('edit wins over page assembly when an artifact already exists', () {
      // Same "website + photos" wording, but an artifact already exists and
      // the prompt references it -> edit path, not a fresh build.
      final plan = planComposition(
        _convo(artifacts: [_htmlArtifact()]),
        'add more photos to the website',
      );
      expect(plan.kind, CompositionKind.editArtifact);
    });
  });
}
