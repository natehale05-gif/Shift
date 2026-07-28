import 'js_sandbox_service.dart';

/// Non-web fallback (compiled for the `flutter test` VM target).
Future<List<ConsoleLine>> runJavaScript(String code, Duration timeout) async {
  return const [
    ConsoleLine(
      level: 'system',
      text: 'JavaScript execution runs in the browser build.',
    ),
  ];
}
