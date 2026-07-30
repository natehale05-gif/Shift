import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';
import 'package:shift_ai/features/studios/studio_response_bank.dart';

Conversation _empty() => Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );

void main() {
  test('a terse image prompt asks a clarifying question instead of '
      'generating', () async {
    final events = await MockChatService()
        .sendMessage(conversation: _empty(), userInput: 'make me a logo')
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.imageStudio);
    final questions =
        events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(questions.trimRight(), endsWith('?'));
    expect(events.whereType<StudioResultReady>(), isEmpty);
    expect(events.last, isA<MessageComplete>());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a turn that asks does not first promise the deliverable', () async {
    // "Here's the image you asked for:" followed by a question is a promise
    // the turn does not keep — the routing intro belongs only to turns that
    // actually generate something.
    final events = await MockChatService()
        .sendMessage(conversation: _empty(), userInput: 'make me a logo')
        .toList();

    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text, isNot(contains('Here\'s the image')));
    expect(text, StudioResponseBank.clarifyingQuestion(
        StudioType.imageStudio, 'make me a logo'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the closed half of the question arrives as tappable options', () async {
    final events = await MockChatService()
        .sendMessage(conversation: _empty(), userInput: 'make me a logo')
        .toList();

    final offered = events.whereType<ChoiceOffered>().single;
    expect(offered.options, isNotEmpty);
    expect(offered.multiSelect, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a descriptive image prompt skips the question and generates '
      'directly', () async {
    final events = await MockChatService()
        .sendMessage(
          conversation: _empty(),
          userInput:
              'make me a minimalist navy blue logo for my coffee shop '
              'called Northbound',
        )
        .toList();

    expect(events.whereType<StudioResultReady>(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('answering the clarifying question merges the two turns and '
      'generates', () async {
    final conversation = Conversation(
      id: 'c1',
      title: 'Test',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'make me a logo',
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: StudioResponseBank.clarifyingQuestion(
              StudioType.imageStudio, 'make me a logo')!,
          studioType: StudioType.imageStudio,
          timestamp: DateTime(2026, 7, 20),
        ),
        // The store appends this turn's own user echo + empty placeholder
        // before a ChatService ever sees the conversation.
        ChatMessage(
          id: 'u2',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'navy blue',
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

    final events = await MockChatService()
        .sendMessage(conversation: conversation, userInput: 'navy blue')
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.imageStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<ImageResult>());
    expect((result as ImageResult).prompt, 'make me a logo navy blue');
    // No second question — one round of clarification is enough.
    final text = events.whereType<MessageDelta>().map((e) => e.chunk).join();
    expect(text.trimRight().endsWith('?'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
