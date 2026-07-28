import 'dart:convert';

import 'js_sandbox_stub.dart' if (dart.library.html) 'js_sandbox_web.dart'
    as impl;

/// One line of captured console output from a sandboxed JavaScript run.
class ConsoleLine {
  /// 'log' | 'info' | 'warn' | 'error' | 'system'
  final String level;
  final String text;

  const ConsoleLine({required this.level, required this.text});
}

/// Message types the sandbox bootstrap posts back to the app.
sealed class SandboxMessage {
  const SandboxMessage();
}

class SandboxConsole extends SandboxMessage {
  final ConsoleLine line;
  const SandboxConsole(this.line);
}

class SandboxDone extends SandboxMessage {
  const SandboxDone();
}

/// Pure codec for the sandbox postMessage protocol — JSON strings of shape
/// `{nonce, type: 'console'|'error'|'done', level?, text?}`. Testable on the
/// VM; the web runner is a thin wrapper around it.
SandboxMessage? parseSandboxMessage(String nonce, Object? data) {
  if (data is! String) return null;
  Map<String, dynamic> decoded;
  try {
    final parsed = jsonDecode(data);
    if (parsed is! Map<String, dynamic>) return null;
    decoded = parsed;
  } catch (_) {
    return null;
  }
  if (decoded['nonce'] != nonce) return null;
  return switch (decoded['type']) {
    'console' => SandboxConsole(ConsoleLine(
        level: decoded['level'] as String? ?? 'log',
        text: decoded['text'] as String? ?? '',
      )),
    'error' => SandboxConsole(ConsoleLine(
        level: 'error',
        text: decoded['text'] as String? ?? 'Unknown error',
      )),
    'done' => const SandboxDone(),
    _ => null,
  };
}

/// The srcdoc bootstrap wrapping user code: patches `console.*` and error
/// handlers to post nonce-tagged JSON messages to the parent, then signals
/// completion. `</script` sequences in user code are escaped so they can't
/// break out of the script element.
String sandboxBootstrapHtml(String nonce, String userCode) {
  final safeCode = userCode.replaceAll('</script', r'<\/script');
  return '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8" /></head>
<body>
<script>
(function () {
  var NONCE = ${jsonEncode(nonce)};
  function post(msg) {
    msg.nonce = NONCE;
    parent.postMessage(JSON.stringify(msg), '*');
  }
  ['log', 'info', 'warn', 'error'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      var text = Array.prototype.map.call(arguments, function (a) {
        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
        catch (e) { return String(a); }
      }).join(' ');
      post({ type: 'console', level: level, text: text });
      original.apply(console, arguments);
    };
  });
  window.onerror = function (message) {
    post({ type: 'error', text: String(message) });
  };
  try {
$safeCode
  } catch (e) {
    post({ type: 'error', text: String(e) });
  }
  post({ type: 'done' });
})();
</script>
</body>
</html>
''';
}

/// Runs JavaScript in a hidden sandboxed iframe and returns everything it
/// printed. Powers the "Run" button on JS artifacts — the local, keyless
/// analysis path.
class JsSandboxService {
  JsSandboxService._();

  static Future<List<ConsoleLine>> run(
    String code, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    return impl.runJavaScript(code, timeout);
  }
}
