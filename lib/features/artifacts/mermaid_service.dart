import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Wraps Mermaid diagram source into a self-contained HTML document that
/// renders the diagram in a sandboxed iframe. The mermaid runtime is bundled
/// as an asset and inlined (no CDN), matching the app's offline-first stance.
///
/// The source is handed to `mermaid.render` as a JSON-encoded JS string rather
/// than embedded in the DOM, so diagram syntax (arrows, braces) never collides
/// with HTML parsing.
class MermaidService {
  MermaidService._();

  static String? _script;

  static Future<String> _loadScript() async {
    return _script ??=
        await rootBundle.loadString('assets/js/mermaid.min.js');
  }

  /// Builds a full HTML page that renders [source] as a diagram. [dark] picks
  /// the mermaid theme so it reads against the app's current background.
  static Future<String> buildHtml(String source, {bool dark = false}) async {
    final script = await _loadScript();
    final theme = dark ? 'dark' : 'default';
    final bg = dark ? '#1c1c1e' : '#ffffff';
    final srcLiteral = jsonEncode(source); // safe JS string literal
    return '''<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  html,body{margin:0;background:$bg;}
  #out{display:flex;justify-content:center;padding:16px;box-sizing:border-box;}
  #out svg{max-width:100%;height:auto;}
  .err{font-family:system-ui,sans-serif;color:#b00020;padding:16px;font-size:14px;}
</style></head>
<body><div id="out"></div>
<script>$script</script>
<script>
  (function(){
    function fail(m){ document.getElementById('out').innerHTML =
      '<div class="err">Could not render diagram: ' + m + '</div>'; }
    try {
      mermaid.initialize({ startOnLoad: false, theme: '$theme', securityLevel: 'strict' });
      mermaid.render('shiftgraph', $srcLiteral).then(function(r){
        document.getElementById('out').innerHTML = r.svg;
      }).catch(function(e){ fail(e && e.message ? e.message : String(e)); });
    } catch (e) { fail(e && e.message ? e.message : String(e)); }
  })();
</script>
</body></html>''';
  }
}
