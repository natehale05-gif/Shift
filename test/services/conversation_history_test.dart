import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/providers/history/conversation_history.dart';

final _bytes = Uint8List.fromList([137, 80, 78, 71]);

ChatMessage _user(String text) => ChatMessage(
      id: 'u',
      conversationId: 'c1',
      role: MessageRole.user,
      text: text,
      timestamp: DateTime(2026, 7, 30),
    );

ChatMessage _assistant({
  String text = '',
  List<MessageBlock> blocks = const [],
  StudioResult? studioResult,
}) =>
    ChatMessage(
      id: 'a',
      conversationId: 'c1',
      role: MessageRole.assistant,
      text: text,
      blocks: blocks,
      studioResult: studioResult,
      timestamp: DateTime(2026, 7, 30),
    );

void main() {
  test('an image-only turn is no longer invisible', () {
    // Every client skipped a turn whose text was empty — which is exactly what
    // an image-only turn is. The model was never told it happened, so a
    // follow-up saying "put it in a website" referred to nothing.
    final turns = buildHistory([
      _user('image of a pink flower'),
      _assistant(blocks: [ImageBlock(alt: 'a pink flower', pngBytes: _bytes)]),
      _user('put it in a website'),
    ]);

    expect(turns, hasLength(3));
    expect(turns[1].role, MessageRole.assistant);
    expect(turns[1].text, contains('a pink flower'));

    // This used to assert the image was *in* the assistant turn, which is the
    // behaviour that made Anthropic reject the whole request:
    // `'image' blocks are not permitted within assistant turns`. The intent of
    // the test is unchanged and still holds — the turn is not invisible and
    // the picture does reach the model — but it rides in the user turn that
    // refers to it.
    expect(turns[1].hasImage, isFalse);
    expect(turns[2].role, MessageRole.user);
    expect(turns[2].hasImage, isTrue);
  });

  test('a voiceover-only turn survives, with its script', () {
    final turns = buildHistory([
      _user('a voiceover about dogs'),
      _assistant(
        studioResult: const AudioResult(
          kind: AudioKind.voice,
          title: 'Voiceover',
          subtitle: 'Voiceover',
          durationSec: 10,
          seed: 1,
          transcript: 'Well now, let me tell ya about dogs.',
        ),
      ),
    ]);

    expect(turns, hasLength(2));
    expect(turns[1].text, contains('voiceover'));
    expect(turns[1].text, contains('let me tell ya about dogs'));
  });

  test('an artifact is referred to, not pasted back in', () {
    // The source is already in the panel; replaying it every turn would spend
    // the context window on something the user can see.
    final turns = buildHistory([
      _user('build me a page'),
      _assistant(blocks: const [
        TextBlock('Here it is.'),
        ArtifactRefBlock(
          artifactId: 'a1',
          title: 'Rye & Co.',
          kind: ArtifactKind.html,
          versionIndex: 0,
        ),
      ]),
    ]);

    expect(turns[1].text, contains('Rye & Co.'));
    expect(turns[1].text, contains('web page'));
  });

  test('thinking and tool chips are left out', () {
    final turns = buildHistory([
      _user('hi'),
      _assistant(blocks: const [
        ThinkingBlock('the user said hi'),
        ToolUseBlock(
            id: 't', tool: 'web_search', label: 'Searching',
            status: ToolUseStatus.done),
        TextBlock('Hello.'),
      ]),
    ]);

    expect(turns[1].text, 'Hello.');
  });

  test('older images fall back to their notes', () {
    // History is unbounded and images are the expensive part. The newest are
    // kept because a follow-up is most likely about those.
    final messages = <ChatMessage>[];
    for (var i = 0; i < 6; i++) {
      messages.add(_user('image $i'));
      messages.add(_assistant(
          blocks: [ImageBlock(alt: 'picture $i', pngBytes: _bytes)]));
    }
    final turns = buildHistory(messages, maxImages: 2);

    expect(turns.where((t) => t.hasImage), hasLength(2));
    // Every turn still says what it made, image attached or not.
    expect(turns.where((t) => t.text.contains('picture')), hasLength(6));
    // The kept ones are the most recent.
    expect(turns.last.hasImage, isTrue);
  });

  test('a provider that cannot see gets the notes instead', () {
    final turns = buildHistory([
      _user('an image'),
      _assistant(blocks: [ImageBlock(alt: 'a pink flower', pngBytes: _bytes)]),
    ], includeImages: false);

    expect(turns[1].hasImage, isFalse);
    expect(turns[1].text, contains('a pink flower'));
  });

  test('older messages with flat text and no blocks still work', () {
    final turns = buildHistory([_user('hi'), _assistant(text: 'Hello.')]);

    expect(turns[1].text, 'Hello.');
  });

  test('a still-streaming empty placeholder is dropped', () {
    // The store appends an empty assistant row before the reply arrives.
    // Nothing to say about it, and an empty turn is a wire error on some APIs.
    final turns = buildHistory([_user('hi'), _assistant()]);

    expect(turns, hasLength(1));
  });

  group('images never ride in an assistant turn', () {
    // The live failure, verbatim from the API:
    //
    //   HTTP 400 invalid_request_error
    //   messages.1.content: 'image' blocks are not permitted within assistant
    //   turns.
    //
    // Generate an image, then say "now build a website and use this image",
    // and the whole request was rejected — so the turn produced an error
    // rather than merely losing the picture.

    test('a generated image is hoisted into the following user turn', () {
      final turns = buildHistory([
        _user('draw me a corgi'),
        _assistant(blocks: [
          ImageBlock(alt: 'a corgi', pngBytes: _bytes),
        ]),
        _user('now build a website for dog treats and use this image'),
      ]);

      for (final turn in turns) {
        if (turn.role == MessageRole.assistant) {
          expect(turn.hasImage, isFalse,
              reason: 'the API rejects the whole request for this');
        }
      }

      final withImage = turns.where((t) => t.hasImage).toList();
      expect(withImage, hasLength(1));
      expect(withImage.single.role, MessageRole.user);
      expect(withImage.single.text, contains('dog treats'),
          reason: 'the picture travels with the request that refers to it');
    });

    test('the assistant still says what it made', () {
      // The note is what a later "use this image" attaches to, so hoisting the
      // bytes must not take the sentence with them.
      final turns = buildHistory([
        _user('draw me a corgi'),
        _assistant(blocks: [
          ImageBlock(alt: 'a corgi', pngBytes: _bytes),
        ]),
        _user('now use it'),
      ]);

      final assistant =
          turns.firstWhere((t) => t.role == MessageRole.assistant);
      expect(assistant.text, contains('[generated image: a corgi]'));
    });

    test('an image with no user turn after it becomes a trailing user turn',
        () {
      // The case that actually broke: the client appends the current message
      // after this list, and merges into this turn.
      final turns = buildHistory([
        _user('draw me a corgi'),
        _assistant(blocks: [
          ImageBlock(alt: 'a corgi', pngBytes: _bytes),
        ]),
      ]);

      expect(turns.last.role, MessageRole.user);
      expect(turns.last.hasImage, isTrue);
    });

    test('several generated images all arrive in one user turn', () {
      final turns = buildHistory([
        _user('draw two'),
        _assistant(blocks: [
          ImageBlock(alt: 'first', pngBytes: _bytes),
          ImageBlock(alt: 'second', pngBytes: _bytes),
        ]),
        _user('use them both'),
      ]);

      final userTurns =
          turns.where((t) => t.role == MessageRole.user && t.hasImage);
      expect(userTurns, hasLength(1));
      expect(
        userTurns.single.parts.whereType<HistoryImage>().length,
        2,
      );
    });

    test('turns still alternate, which is what the API requires', () {
      final turns = buildHistory([
        _user('draw me a corgi'),
        _assistant(blocks: [
          ImageBlock(alt: 'a corgi', pngBytes: _bytes),
          const TextBlock('Here it is.'),
        ]),
        _user('now a website'),
        _assistant(blocks: [const TextBlock('Done.')]),
      ]);

      for (var i = 1; i < turns.length; i++) {
        expect(turns[i].role, isNot(turns[i - 1].role),
            reason: 'two turns in a row with the same role is a 400');
      }
    });

    test('with images off, nothing carries bytes and the notes remain', () {
      final turns = buildHistory([
        _user('draw me a corgi'),
        _assistant(blocks: [
          ImageBlock(alt: 'a corgi', pngBytes: _bytes),
        ]),
        _user('now a website'),
      ], includeImages: false);

      expect(turns.any((t) => t.hasImage), isFalse);
      expect(
        turns.map((t) => t.text).join(' '),
        contains('[generated image: a corgi]'),
      );
    });
  });
}
