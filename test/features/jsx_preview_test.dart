import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/artifacts/jsx_preview.dart';

const _component = '''
import React, { useState } from "react";

export default function App() {
  const [n, setN] = useState(0);
  return <button onClick={() => setN(n + 1)}>Clicked {n}</button>;
}
''';

String page(String code, {bool typescript = false}) => JsxPreview.buildPage(
      code: code,
      typescript: typescript,
      react: '/*react*/',
      reactDom: '/*react-dom*/',
      transform: '/*transform*/',
    );

void main() {
  group('handles', () {
    test('the React fence languages', () {
      for (final lang in ['jsx', 'tsx', 'JSX', ' react ', 'typescriptreact']) {
        expect(JsxPreview.handles(lang), isTrue, reason: lang);
      }
    });

    test('a plain js fence that is really React', () {
      // Models label React as ```javascript at least as often as ```jsx, so a
      // language-only test leaves the common case showing source.
      expect(JsxPreview.handles('javascript', _component), isTrue);
      expect(JsxPreview.handles('js', _component), isTrue);
    });

    test('ordinary JavaScript is left as source', () {
      // A blank preview pane is worse than a code listing, so the sniff needs
      // both a React import and a returned tag — neither alone.
      expect(JsxPreview.handles('javascript', 'const a = 1 < 2;'), isFalse);
      expect(
          JsxPreview.handles('javascript',
              'import React from "react";\nexport const NAME = "x";'),
          isFalse,
          reason: 'imports React but renders nothing');
      expect(
          JsxPreview.handles('javascript', 'function f() { return <div/>; }'),
          isFalse,
          reason: 'a tag without React is not a component we can mount');
    });

    test('other languages are never claimed', () {
      for (final lang in ['python', 'html', 'dart', 'css', null, '']) {
        expect(JsxPreview.handles(lang, _component), isFalse,
            reason: '$lang');
      }
    });
  });

  group('isTypeScript', () {
    test('the typed fences', () {
      expect(JsxPreview.isTypeScript('tsx'), isTrue);
      expect(JsxPreview.isTypeScript('typescript'), isTrue);
      expect(JsxPreview.isTypeScript('jsx'), isFalse);
      expect(JsxPreview.isTypeScript('javascript'), isFalse);
    });
  });

  group('buildPage', () {
    test('the source is JSON-encoded, not interpolated', () {
      // Arbitrary source contains quotes, backslashes and `</script>`; pasting
      // it in raw breaks out of the script tag. The mermaid renderer learned
      // this the same way.
      final html = page('const s = "hi";\n// </script>\n');
      // Quotes survive as escaped JSON rather than ending the string literal.
      expect(html, contains(r'\"hi\"'));
      // And the closing tag is escaped, so it cannot end this page's script
      // block early — jsonEncode alone leaves `/` untouched, which is exactly
      // how source spills out of a <script> and into the document.
      expect(html, contains(r'<\/script>'));
      expect('</script>'.allMatches(html).length, 4,
          reason: 'only the four tags this page opens');
    });

    test('the three libraries are inlined, not linked', () {
      final html = page(_component);
      expect(html, contains('/*react*/'));
      expect(html, contains('/*react-dom*/'));
      expect(html, contains('/*transform*/'));
      expect(html, isNot(contains('src="http')),
          reason: 'a preview that needs the network fails offline');
    });

    test('the typescript flag reaches the transform', () {
      expect(page(_component, typescript: true), contains('typescript: true'));
      expect(page(_component), contains('typescript: false'));
    });

    test('failures are shown rather than swallowed', () {
      final html = page(_component);
      for (final stage in [
        'Could not compile this component.',
        'The component threw while loading.',
        'The component threw while rendering.',
        'No component to render.',
      ]) {
        expect(html, contains(stage), reason: stage);
      }
    });

    test('an unresolvable import fails by name', () {
      // "undefined is not a function" three frames into a bundle says nothing;
      // naming the module says exactly what to remove.
      expect(page(_component), contains('which would need a build step'));
    });

    test('a component is found however it was exported', () {
      final html = page(_component);
      expect(html, contains('exported.default'));
      expect(html, contains('exported.App'));
      expect(html, contains("typeof exported[key] === 'function'"));
    });
  });
}
