import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/artifact.dart';

/// What an artifact saves as.
void main() {
  Artifact of(ArtifactKind kind, {String title = 'Coffee shop', String? lang}) =>
      Artifact(
        id: 'a1',
        conversationId: 'c1',
        title: title,
        kind: kind,
        language: lang,
        versions: [
          ArtifactVersion(content: 'x', createdAt: DateTime(2026)),
        ],
      );

  test('the extension comes from the kind, not the title', () {
    // A page saved as `.txt` opens in a text editor and looks like the app
    // produced nothing.
    expect(of(ArtifactKind.html).filename, 'coffee-shop.html');
    expect(of(ArtifactKind.svg).filename, 'coffee-shop.svg');
    expect(of(ArtifactKind.markdown).filename, 'coffee-shop.md');
  });

  test("a code artifact keeps its own language's extension", () {
    // `.txt` for a Python file would be the app forgetting what it just wrote.
    expect(of(ArtifactKind.code, title: 'Sort it', lang: 'python').filename,
        'sort-it.py');
    expect(of(ArtifactKind.code, title: 'Sort it', lang: 'dart').filename,
        'sort-it.dart');
  });

  test('an unknown language still saves as something openable', () {
    expect(of(ArtifactKind.code, title: 'Thing', lang: 'brainfuck').filename,
        'thing.txt');
    expect(of(ArtifactKind.code, title: 'Thing').filename, 'thing.txt');
  });

  test('a title that slugifies to nothing still has a name', () {
    expect(of(ArtifactKind.html, title: '???').filename, 'artifact.html');
    expect(of(ArtifactKind.html, title: '').filename, 'artifact.html');
  });

  test('two different titles are two different files', () {
    // The v1 regression that made every download collide.
    expect(of(ArtifactKind.html, title: 'Coffee shop').filename,
        isNot(of(ArtifactKind.html, title: 'Bakery').filename));
  });

  test('every kind has a type a browser and an OS both understand', () {
    for (final kind in ArtifactKind.values) {
      expect(of(kind).mimeType, contains('/'), reason: kind.name);
    }
    expect(of(ArtifactKind.html).mimeType, 'text/html');
  });
}
