import 'dart:async';
import 'dart:math';

import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_type.dart';
import 'chat_service.dart';
import 'studio_response_bank.dart';

/// Simulates the "middleware AI" that routes to specialized studio models.
/// Everything here is fabricated locally with artificial delay to mimic a
/// real streaming backend — there is no network call in this build. Swap
/// this out for a real [ChatService] implementation once a backend exists.
class MockChatService implements ChatService {
  final Random _random = Random();

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
  }) {
    final controller = StreamController<ChatEvent>();
    _run(controller, userInput, structuredRequest);
    return controller.stream;
  }

  Future<void> _run(
    StreamController<ChatEvent> controller,
    String userInput,
    StudioRequest? structuredRequest,
  ) async {
    try {
      final studio = structuredRequest?.studioType ??
          StudioResponseBank.detectStudio(userInput);

      await _delay(400, 900);
      controller.add(RoutingDetected(studio));

      final introText = structuredRequest != null
          ? StudioResponseBank.routingIntro(studio, structuredRequest.summary)
          : StudioResponseBank.routingIntro(studio, userInput);

      await _streamText(controller, introText);

      if (studio != StudioType.middleware) {
        await _delay(500, 1100);
        final result = structuredRequest != null
            ? StudioResponseBank.buildResult(structuredRequest)
            : StudioResponseBank.buildResultFromFreeform(studio, userInput);
        controller.add(StudioResultReady(result));

        final followUp = StudioResponseBank.studioFollowUp(studio);
        if (followUp.isNotEmpty) {
          await _streamText(controller, '\n\n$followUp');
        }
      }

      controller.add(const MessageComplete());
    } catch (e) {
      controller.add(MessageError(e.toString()));
    } finally {
      await controller.close();
    }
  }

  Future<void> _streamText(
    StreamController<ChatEvent> controller,
    String text,
  ) async {
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (controller.isClosed) return;
      final chunk = i == 0 ? words[i] : ' ${words[i]}';
      controller.add(MessageDelta(chunk));
      await Future.delayed(Duration(milliseconds: 18 + _random.nextInt(35)));
    }
  }

  Future<void> _delay(int minMs, int maxMs) =>
      Future.delayed(Duration(milliseconds: minMs + _random.nextInt(maxMs - minMs)));
}
