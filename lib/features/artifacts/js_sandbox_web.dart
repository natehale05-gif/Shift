// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:math';

import 'js_sandbox_service.dart';

/// Real implementation: hidden sandboxed iframe + postMessage protocol.
Future<List<ConsoleLine>> runJavaScript(String code, Duration timeout) async {
  final nonce = List.generate(4, (_) => Random().nextInt(1 << 32).toRadixString(16)).join('-');
  final lines = <ConsoleLine>[];
  final done = Completer<void>();

  late StreamSubscription<html.MessageEvent> subscription;
  subscription = html.window.onMessage.listen((event) {
    switch (parseSandboxMessage(nonce, event.data)) {
      case SandboxConsole(:final line):
        lines.add(line);
      case SandboxDone():
        if (!done.isCompleted) done.complete();
      case null:
        break;
    }
  });

  final iframe = html.IFrameElement()..style.display = 'none';
  iframe.setAttribute('sandbox', 'allow-scripts');
  iframe.srcdoc = sandboxBootstrapHtml(nonce, code);
  html.document.body?.append(iframe);

  try {
    await done.future.timeout(timeout, onTimeout: () {
      lines.add(ConsoleLine(
        level: 'system',
        text: 'Stopped after ${timeout.inSeconds}s — '
            'the script did not finish (infinite loop or long task?).',
      ));
    });
  } finally {
    await subscription.cancel();
    iframe.remove();
  }
  return lines;
}
