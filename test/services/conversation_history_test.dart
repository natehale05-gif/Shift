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
    expect(turns[1].hasImage, isTrue);
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
}
