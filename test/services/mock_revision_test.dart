import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/studios/studio_response_bank.dart';
import 'package:shift_ai/turn/backends/mock_revision.dart';

String _page() => StudioResponseBank.htmlArtifactContent('Bakery landing page');

int _headingSize(String html) {
  final rule = RegExp(r'h1\s*\{([^}]*)\}').firstMatch(html)!;
  return int.parse(
      RegExp(r'font-size:\s*(\d+)px').firstMatch(rule.group(1)!)!.group(1)!);
}

String _ruleBackground(String html, String selector) {
  final rule =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}').firstMatch(html)!;
  return RegExp(r'background:\s*([^;]+);').firstMatch(rule.group(1)!)!.group(1)!.trim();
}

void main() {
  group('heading size', () {
    test('bigger increases the h1 font-size', () {
      final before = _headingSize(_page());
      final out = applyMockRevision(_page(), 'make the heading bigger')!;
      expect(_headingSize(out.html), greaterThan(before));
    });

    test('smaller decreases it', () {
      final before = _headingSize(_page());
      final out = applyMockRevision(_page(), 'can you make the title smaller')!;
      expect(_headingSize(out.html), lessThan(before));
    });
  });

  group('colours', () {
    test('"make the button red" changes the CTA, not the page background', () {
      final page = _page();
      final bodyBefore = _ruleBackground(page, 'body');
      final out = applyMockRevision(page, 'make the button red')!;

      expect(_ruleBackground(out.html, '.cta'), '#FF3B30');
      expect(_ruleBackground(out.html, 'body'), bodyBefore);
    });

    test('"make the background navy" changes the body, not the CTA', () {
      final page = _page();
      final ctaBefore = _ruleBackground(page, '.cta');
      final out = applyMockRevision(page, 'make the background navy')!;

      expect(_ruleBackground(out.html, 'body'), '#1B2A4A');
      expect(_ruleBackground(out.html, '.cta'), ctaBefore);
    });

    test('a bare colour reads as the call-to-action', () {
      final out = applyMockRevision(_page(), 'make it green')!;
      expect(_ruleBackground(out.html, '.cta'), '#34C759');
    });

    test('an explicit hex wins over a named colour', () {
      final out = applyMockRevision(_page(), 'make the button #123ABC')!;
      expect(_ruleBackground(out.html, '.cta'), '#123ABC');
    });
  });

  group('heading text', () {
    test('sets the h1 and leaves the styles alone', () {
      final before = _headingSize(_page());
      final out = applyMockRevision(
          _page(), 'change the heading to Fresh Sourdough Daily')!;

      expect(out.html, contains('<h1>Fresh Sourdough Daily</h1>'));
      expect(_headingSize(out.html), before);
    });

    test('"make it say X" also works', () {
      final out = applyMockRevision(_page(), 'make it say Open Late')!;
      expect(out.html, contains('<h1>Open Late</h1>'));
    });
  });

  test('adding a section keeps what was already there', () {
    final out = applyMockRevision(_page(), 'add a footer')!;
    expect(out.html, contains('New footer'));
    expect(out.html, contains('Bakery landing page'));
    expect(out.html, contains('</body>'));
  });

  test('edits compose — each one builds on the last', () {
    // The bug this whole wave exists for: revisions used to be rebuilt from
    // the template, so an earlier change was silently discarded.
    final red = applyMockRevision(_page(), 'make the button red')!;
    final bigger = applyMockRevision(red.html, 'make the heading bigger')!;

    expect(_ruleBackground(bigger.html, '.cta'), '#FF3B30',
        reason: 'the earlier colour change must survive');
    expect(_headingSize(bigger.html), greaterThan(_headingSize(_page())));
  });

  test('an unrecognised edit returns null rather than inventing a page', () {
    expect(applyMockRevision(_page(), 'make it more professional'), isNull);
    expect(applyMockRevision(_page(), 'improve the conversion rate'), isNull);
  });
}
