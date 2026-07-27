import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/router/model_router.dart';

void main() {
  group('parseRouteJson', () {
    test('parses every route value', () {
      expect(parseRouteJson('{"route":"chat"}'), ChatRoute.chat);
      expect(parseRouteJson('{"route":"code"}'), ChatRoute.code);
      expect(parseRouteJson('{"route":"image_gen"}'), ChatRoute.imageGen);
      expect(parseRouteJson('{"route":"deep_research"}'),
          ChatRoute.deepResearch);
    });

    test('tolerates code fences and whitespace', () {
      expect(
        parseRouteJson('```json\n{"route":"web_search"}\n```'),
        ChatRoute.webSearch,
      );
    });

    test('returns null on junk or unknown routes', () {
      expect(parseRouteJson('not json'), isNull);
      expect(parseRouteJson('{"route":"teleport"}'), isNull);
      expect(parseRouteJson('{"other":"chat"}'), isNull);
    });
  });

  group('keywordRoute fallback', () {
    test('maps studio keywords onto routes', () {
      expect(keywordRoute('write a python function'), ChatRoute.code);
      expect(keywordRoute('make me a logo'), ChatRoute.imageGen);
      expect(keywordRoute('drop a lo-fi beat'), ChatRoute.audio);
      expect(keywordRoute('write ad copy for my brand'), ChatRoute.writing);
      expect(keywordRoute('what is the latest news on chips'),
          ChatRoute.webSearch);
      expect(keywordRoute('how are you today?'), ChatRoute.webSearch,
          reason: '"today" is a search keyword — acceptable heuristic');
      expect(keywordRoute('tell me about philosophy'), ChatRoute.chat);
    });
  });

  test('routes carry the right studio identity for the routing chip', () {
    expect(ChatRoute.code.studioType, StudioType.codeStudio);
    expect(ChatRoute.imageGen.studioType, StudioType.imageStudio);
    expect(ChatRoute.chat.studioType, StudioType.middleware);
  });
}
