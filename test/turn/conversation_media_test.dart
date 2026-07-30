import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/message_block.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/turn/conversation_media.dart';

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

Conversation _conversation(List<ChatMessage> messages) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      messages: messages,
    );

/// The conversation from the bug report: an image was generated, nothing else.
Conversation _afterGeneratingAnImage() => _conversation([
      _user('image of a pink flower'),
      _assistant(blocks: [
        const TextBlock('Here it is.'),
        ImageBlock(alt: 'photorealistic pink flower', pngBytes: _bytes),
      ]),
    ]);

void main() {
  group('latestGeneratedImage', () {
    test('finds an image the live path produced', () {
      final image = latestGeneratedImage(_afterGeneratingAnImage());

      expect(image, isNotNull);
      expect(image!.alt, 'photorealistic pink flower');
      expect(image.pngBytes, _bytes);
    });

    test('finds demo mode\'s image, which is a seed rather than bytes', () {
      final image = latestGeneratedImage(_conversation([
        _user('a logo'),
        _assistant(
            studioResult: const ImageResult(
          prompt: 'a logo',
          aspectRatio: '1:1',
          stylePreset: 'clean',
          count: 1,
          seed: 42,
        )),
      ]));

      expect(image, isNotNull);
      expect(image!.seed, 42);
      expect(image.alt, 'a logo');
    });

    test('takes the most recent one', () {
      final image = latestGeneratedImage(_conversation([
        _user('a logo'),
        _assistant(blocks: [ImageBlock(alt: 'first', pngBytes: _bytes)]),
        _user('another'),
        _assistant(blocks: [ImageBlock(alt: 'second', pngBytes: _bytes)]),
      ]));

      expect(image!.alt, 'second');
    });

    test('a conversation with no image has none', () {
      expect(
        latestGeneratedImage(_conversation([
          _user('hello'),
          _assistant(text: 'hi', blocks: [const TextBlock('hi')]),
        ])),
        isNull,
      );
    });
  });

  group('existingImageForPage', () {
    test('"now put this image in the website" — the reported case', () {
      // The whole bug: this returned nothing, so the turn asked a provider for
      // a second flower, or handed the model a page to write about a picture
      // it cannot see.
      final image = existingImageForPage(
          _afterGeneratingAnImage(), 'now put this image in the website');

      expect(image, isNotNull);
      expect(image!.pngBytes, _bytes);
    });

    test('"put it in a website selling pink flowers" — reported again', () {
      // Most people refer to the picture with a bare pronoun, because it is
      // right there on screen. Requiring the noun ("this *image*") meant this
      // fell through and the model invented an SVG flower instead.
      expect(
        existingImageForPage(
            _afterGeneratingAnImage(), 'put it in a website selling pink flowers'),
        isNotNull,
      );
    });

    test('other phrasings of the same request', () {
      for (final prompt in [
        'put that photo on the page',
        'use this image in the site',
        'add the picture you made to the landing page',
        'build a website around this image',
        'use it on a landing page',
        'turn it into a website',
        'make a site with it',
        'add it to a portfolio page',
        'build me a shop page featuring it',
      ]) {
        expect(existingImageForPage(_afterGeneratingAnImage(), prompt), isNotNull,
            reason: prompt);
      }
    });

    test('a pronoun that is the destination, not the picture', () {
      // "in it" points at the page being built, not at the image.
      expect(
        existingImageForPage(_afterGeneratingAnImage(),
            'build a landing page and put a contact form in it'),
        isNull,
      );
    });

    test('"a hero image" still asks for a new one', () {
      // Indefinite: nothing is being pointed at, so this must keep going to
      // the image provider rather than reusing whatever was made before.
      expect(
        existingImageForPage(
            _afterGeneratingAnImage(), 'add a hero image to the website'),
        isNull,
      );
    });

    test('an image request with no page is left alone', () {
      expect(
        existingImageForPage(_afterGeneratingAnImage(), 'make this image bigger'),
        isNull,
      );
    });

    test('a page request with no image in the conversation is left alone', () {
      expect(
        existingImageForPage(
            _conversation([_user('hi')]), 'put this image in the website'),
        isNull,
      );
    });
  });
}
