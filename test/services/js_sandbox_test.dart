import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/artifact.dart';
import 'package:shift_ai/features/artifacts/js_sandbox_service.dart';
import 'package:shift_ai/core/state/artifact_panel_store.dart';

void main() {
  group('parseSandboxMessage', () {
    test('accepts console lines with the matching nonce', () {
      final message = parseSandboxMessage(
        'n1',
        '{"nonce":"n1","type":"console","level":"warn","text":"careful"}',
      );
      final line = (message as SandboxConsole).line;
      expect(line.level, 'warn');
      expect(line.text, 'careful');
    });

    test('maps error messages to error-level console lines', () {
      final message = parseSandboxMessage(
        'n1',
        '{"nonce":"n1","type":"error","text":"ReferenceError: x"}',
      );
      expect((message as SandboxConsole).line.level, 'error');
    });

    test('recognizes done', () {
      expect(
        parseSandboxMessage('n1', '{"nonce":"n1","type":"done"}'),
        isA<SandboxDone>(),
      );
    });

    test('rejects wrong nonce, non-string data, and junk', () {
      expect(
        parseSandboxMessage('n1', '{"nonce":"OTHER","type":"done"}'),
        isNull,
      );
      expect(parseSandboxMessage('n1', 42), isNull);
      expect(parseSandboxMessage('n1', 'not json'), isNull);
      expect(parseSandboxMessage('n1', '{"nonce":"n1","type":"weird"}'),
          isNull);
    });
  });

  group('sandboxBootstrapHtml', () {
    test('embeds the user code and nonce', () {
      final html = sandboxBootstrapHtml('n42', 'console.log("hi")');
      expect(html, contains('console.log("hi")'));
      expect(html, contains('"n42"'));
    });

    test('escapes </script> so code cannot break out of the sandbox tag',
        () {
      final html =
          sandboxBootstrapHtml('n1', 'var s = "</script><img src=x>";');
      expect(html.contains('"</script><img'), isFalse);
      expect(html, contains(r'<\/script'));
    });
  });

  group('ArtifactPanelStore', () {
    test('open/select/close lifecycle', () {
      final store = ArtifactPanelStore();
      expect(store.isOpen, isFalse);

      store.open('a1', versionIndex: 2);
      expect(store.isOpen, isTrue);
      expect(store.versionIndex, 2);

      store.selectTab(ArtifactTab.code);
      store.selectVersion(1);
      expect(store.tab, ArtifactTab.code);
      expect(store.versionIndex, 1);

      store.close();
      expect(store.isOpen, isFalse);
      expect(store.tab, ArtifactTab.preview);
      expect(store.versionIndex, 0);
    });

    test('clampVersion pulls an out-of-range pointer back', () {
      final store = ArtifactPanelStore();
      store.open('a1', versionIndex: 5);
      store.clampVersion(2);
      expect(store.versionIndex, 1);
    });
  });

  test('withNewVersion appends and latest points at it', () {
    final artifact = Artifact(
      id: 'a1',
      conversationId: 'c1',
      title: 'page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(content: 'v1', createdAt: DateTime(2026, 1, 1)),
      ],
    );
    final updated = artifact.withNewVersion('v2', DateTime(2026, 1, 2));
    expect(updated.versions, hasLength(2));
    expect(updated.latest.content, 'v2');
    // Original is untouched (immutability).
    expect(artifact.versions, hasLength(1));
  });
}
