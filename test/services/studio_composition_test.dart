import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/artifact.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_result.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/services/artifact_composition.dart';
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
      expect(plan.editKind, ArtifactMediaKind.image);
    });

    test('adding audio to an existing site is an audio edit (Music host)', () {
      final plan = planComposition(
        _convo(artifacts: [_htmlArtifact()]),
        'add background music to the website',
      );
      expect(plan.kind, CompositionKind.editArtifact);
      expect(plan.host, StudioType.musicStudio);
      expect(plan.editKind, ArtifactMediaKind.audio);
      expect(plan.editTarget?.id, 'art1');
    });

    test('adding a video to an existing site is a video edit (Video host)', () {
      final plan = planComposition(
        _convo(artifacts: [_htmlArtifact()]),
        'add a video to the website',
      );
      expect(plan.kind, CompositionKind.editArtifact);
      expect(plan.host, StudioType.videoStudio);
      expect(plan.editKind, ArtifactMediaKind.video);
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

    test('a page request that names a non-image contributor is page '
        'assembly too', () {
      final plan = planComposition(
        _convo(),
        'build me a bakery website with a soundtrack and a headline',
      );
      expect(plan.kind, CompositionKind.pageAssembly);
      expect(plan.contributors, contains(StudioType.musicStudio));
      expect(plan.contributors, contains(StudioType.copyScriptsStudio));
      expect(plan.contributors, isNot(contains(StudioType.videoStudio)));
    });

    test('"add a hero image to the website" with no artifact yet is NOT a '
        'fresh page build — the wording refers to an existing site', () {
      final plan =
          planComposition(_convo(), 'add a hero image to the website');
      expect(plan.kind, CompositionKind.none);
    });

    test('"write and narrate…" is Copy -> Voice (narratedScript)', () {
      final plan =
          planComposition(_convo(), 'write and narrate a welcome message');
      expect(plan.kind, CompositionKind.narratedScript);
      expect(plan.host, StudioType.voiceAvatarStudio);
      expect(plan.contributors, contains(StudioType.copyScriptsStudio));
    });

    test('"write a video script and make it" is Copy -> Video', () {
      final plan = planComposition(
          _convo(), 'write a video script and make the video');
      expect(plan.kind, CompositionKind.scriptedVideo);
      expect(plan.host, StudioType.videoStudio);
    });

    test('"write a jingle" is Copy -> Music', () {
      final plan =
          planComposition(_convo(), 'write a jingle for my bakery');
      expect(plan.kind, CompositionKind.jingle);
      expect(plan.host, StudioType.musicStudio);
    });

    test('narrating user-provided text (no write signal) stays single '
        'studio', () {
      final plan =
          planComposition(_convo(), 'narrate this line for me please');
      expect(plan.kind, CompositionKind.none);
    });

    test('a page that also names video prefers page assembly over '
        'scriptedVideo', () {
      final plan = planComposition(
          _convo(), 'write a website with a video clip');
      expect(plan.kind, CompositionKind.pageAssembly);
    });

    test('"a talking avatar that says hello" is Image + Voice', () {
      final plan =
          planComposition(_convo(), 'make a talking avatar that says hello');
      expect(plan.kind, CompositionKind.talkingAvatar);
      expect(plan.host, StudioType.avatarStudio);
      expect(plan.contributors, containsAll(
          [StudioType.imageStudio, StudioType.voiceStudio]));
    });

    test('a portrait + voiceover request is also a talking avatar', () {
      final plan = planComposition(
          _convo(), 'generate a portrait with a voiceover');
      expect(plan.kind, CompositionKind.talkingAvatar);
    });

    test('"narrate this over background music" is Voice + Music '
        '(scoredNarration)', () {
      final plan = planComposition(
          _convo(), 'narrate this line over background music');
      expect(plan.kind, CompositionKind.scoredNarration);
      expect(plan.contributors, contains(StudioType.musicStudio));
    });

    test('copy-fed wins over a media pair when a write signal is present', () {
      // "write and narrate ... with music" -> narratedScript, not
      // scoredNarration (the write signal routes to Copy first).
      final plan = planComposition(
          _convo(), 'write and narrate a welcome message with background music');
      expect(plan.kind, CompositionKind.narratedScript);
    });
  });

  group('mediaPairAudio', () {
    test('talkingAvatar is a voice card carrying the script', () {
      final r = mediaPairAudio(
          CompositionKind.talkingAvatar, 'hello avatar', 'Hi there!');
      expect(r.kind, AudioKind.voice);
      expect(r.transcript, 'Hi there!');
    });

    test('scoredNarration is a music bed with the narration as transcript',
        () {
      final r = mediaPairAudio(
          CompositionKind.scoredNarration, 'a calm intro', 'Welcome in.');
      expect(r.kind, AudioKind.music);
      expect(r.transcript, 'Welcome in.');
    });
  });

  group('copyFedResult', () {
    test('narratedScript carries the script as a voice transcript', () {
      final result =
          copyFedResult(CompositionKind.narratedScript, 'welcome', 'Hello!');
      expect(result, isA<AudioResult>());
      final audio = result as AudioResult;
      expect(audio.kind, AudioKind.voice);
      expect(audio.transcript, 'Hello!');
    });

    test('scriptedVideo carries the script as the video prompt', () {
      final result =
          copyFedResult(CompositionKind.scriptedVideo, 'promo', 'Shot 1...');
      expect(result, isA<VideoResult>());
      expect((result as VideoResult).prompt, 'Shot 1...');
    });

    test('jingle is a music result with a title', () {
      final result =
          copyFedResult(CompositionKind.jingle, 'bakery', 'la la la');
      expect(result, isA<AudioResult>());
      expect((result as AudioResult).kind, AudioKind.music);
      expect(result.title, isNotEmpty);
    });
  });

  group('embedCopyIntoPage', () {
    const template = '<!DOCTYPE html><html><body><main class="hero">'
        '<h1>Old Title</h1><p>Old body copy here.</p>'
        '<a class="cta" href="#">Get started</a></main></body></html>';

    test('replaces hero headline, body, and CTA text', () {
      final out = embedCopyIntoPage(template,
          headline: 'Fresh Bakes Daily',
          body: 'Northbound Bakery, reimagined.',
          cta: 'Order now');
      expect(out, contains('<h1>Fresh Bakes Daily</h1>'));
      expect(out, contains('<p>Northbound Bakery, reimagined.</p>'));
      expect(out, contains('>Order now</a>'));
      expect(out, isNot(contains('Old Title')));
      expect(out, isNot(contains('Old body copy')));
    });

    test('is a no-op when the piece is not present (a page with no hero)', () {
      const fragment = '<body><section>hi</section></body>';
      expect(embedCopyIntoPage(fragment, headline: 'x'), fragment);
    });

    test('escapes HTML in the copy', () {
      final out = embedCopyIntoPage(template, headline: 'Tom & <Jerry>');
      expect(out, contains('Tom &amp; &lt;Jerry&gt;'));
    });
  });

  group('embedAudioPlayer / embedVideoBlock', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    const html = '<!DOCTYPE html><html><body><h1>Hi</h1></body></html>';

    test('audio player embeds a controllable WAV data URI', () {
      final out = embedAudioPlayer(html, bytes, label: 'Bakery theme');
      expect(out, contains('<audio controls'));
      expect(out, contains('data:audio/wav;base64,${base64Encode(bytes)}'));
      expect(out, contains('Bakery theme'));
      // Inserted right after <body>, before the existing content.
      expect(out.indexOf('<audio'), lessThan(out.indexOf('<h1>')));
    });

    test('video block embeds a poster image + simulated-video caption', () {
      final out = embedVideoBlock(html, bytes, label: 'Promo');
      expect(out, contains('data:image/png;base64,${base64Encode(bytes)}'));
      expect(out, contains('Simulated video · Promo'));
      expect(out.indexOf('<figure'), lessThan(out.indexOf('<h1>')));
    });
  });

  group('assemblePage', () {
    const template = '<!DOCTYPE html><html><body><main class="hero">'
        '<h1>Old</h1><p>Old.</p><a class="cta" href="#">Go</a>'
        '</main></body></html>';
    final img = Uint8List.fromList([9, 9]);
    final wav = Uint8List.fromList([8, 8]);
    final poster = Uint8List.fromList([7, 7]);

    test('weaves every contributor into one page, gallery on top', () {
      final out = assemblePage(
        template,
        images: [img, img],
        copy: (headline: 'New Title', body: 'New body.', cta: 'Buy'),
        audioWav: wav,
        videoPoster: poster,
      );
      expect(out, contains('<h1>New Title</h1>'));
      expect(out, contains('<audio controls'));
      expect(out, contains('Simulated video'));
      expect('<img'.allMatches(out).length, 3); // 2 gallery + 1 video poster
      // Display order after <body>: gallery, audio, video.
      expect(out.indexOf('grid-template-columns'),
          lessThan(out.indexOf('<audio')));
      expect(out.indexOf('<audio'), lessThan(out.indexOf('Simulated video')));
    });

    test('embeds only the contributors provided', () {
      final out = assemblePage(template, audioWav: wav);
      expect(out, contains('<audio controls'));
      expect(out.contains('<img'), isFalse);
      expect(out.contains('Simulated video'), isFalse);
      expect(out, contains('<h1>Old</h1>')); // copy untouched
    });
  });
}
