import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/tools.dart';
import 'package:shift/agents/workspace.dart';
import 'package:shift/agents/workspace_local_stub.dart'
    if (dart.library.io) 'package:shift/agents/workspace_local_io.dart';

/// The agent's hands, against a real directory.
///
/// A fake filesystem would pass every test here and prove nothing about the one
/// property that matters — that a path cannot escape the root — because
/// escaping is a property of real paths, real `..`, and real symlinks.
void main() {
  late Directory dir;
  late LocalWorkspace workspace;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-ws');
    workspace = LocalWorkspace(dir.path);
    await workspace.writeText('lib/main.dart', 'void main() {}\n');
    await workspace.writeText('lib/app.dart', 'class App {}\n');
    await workspace.writeText('README.md', '# Title\nsome prose\n');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('it cannot leave the workspace', () {
    // The security boundary of the whole mode. An agent is a model choosing
    // what to open; if this were advisory, one confused generation reads a
    // private key.
    test('a relative escape is refused', () {
      expect(() => workspace.readText('../../etc/passwd'),
          throwsA(isA<OutsideWorkspace>()));
    });

    test('an absolute path is refused', () {
      expect(() => workspace.readText('/etc/passwd'),
          throwsA(isA<OutsideWorkspace>()));
    });

    test('a path that climbs out and back in is allowed', () {
      // `lib/../README.md` is inside. Refusing it would be a check that reads
      // text rather than paths.
      expect(workspace.readText('lib/../README.md'), completes);
    });

    test('a symlink pointing out of the tree is refused', () async {
      // The trick a purely textual check misses: the path never contains `..`,
      // and what it resolves to is somewhere else entirely.
      final outside = await Directory.systemTemp.createTemp('shift-outside');
      addTearDown(() => outside.delete(recursive: true));
      await File('${outside.path}/secret.txt').writeAsString('do not read me');
      await Link('${dir.path}/escape').create(outside.path);

      expect(() => workspace.readText('escape/secret.txt'),
          throwsA(isA<OutsideWorkspace>()));
    });

    test('a write cannot land outside either', () {
      // Checked on the *parent*, because the file does not exist yet and so
      // cannot be resolved — and the parent is what decides where it lands.
      expect(() => workspace.writeText('../escaped.txt', 'x'),
          throwsA(isA<OutsideWorkspace>()));
    });

    test('deleting the root itself is refused', () {
      // `delete('.')` is a plausible thing for a model to emit, and it would
      // take the repository with it.
      expect(() => workspace.delete('.'), throwsA(isA<OutsideWorkspace>()));
    });
  });

  group('finding things', () {
    test('a glob crossing directories finds nested files', () async {
      expect(await workspace.glob('**/*.dart'),
          containsAll(['lib/app.dart', 'lib/main.dart']));
    });

    test('a single star does not cross a directory', () async {
      expect(await workspace.glob('*.md'), ['README.md']);
      expect(await workspace.glob('*.dart'), isEmpty);
    });

    test('`**/x` matches at the root too', () async {
      // Otherwise `**/*.md` finds nothing in a flat repository, which is the
      // most confusing possible answer.
      expect(await workspace.glob('**/*.md'), ['README.md']);
    });

    test('noise directories are skipped', () async {
      await workspace.writeText('.git/objects/aa/bb', 'binary');
      await workspace.writeText('node_modules/x/index.js', 'x');
      final all = await workspace.glob('**');
      expect(all.where((f) => f.startsWith('.git')), isEmpty);
      expect(all.where((f) => f.startsWith('node_modules')), isEmpty);
    });

    test('grep returns the path, the line number and the line', () async {
      final hits = await workspace.grep('some');
      expect(hits.single.path, 'README.md');
      expect(hits.single.line, 2);
      expect(hits.single.text, 'some prose');
    });
  });

  group('running a command', () {
    test('it runs in the workspace, not wherever the app was started',
        () async {
      final result = await workspace.run('pwd', const []);
      expect(result.ok, isTrue);
      // `resolveSymbolicLinksSync` because macOS puts temp dirs behind
      // `/private`, so the string the shell reports is not the one we joined.
      expect(result.stdout.trim(),
          Directory(workspace.root).resolveSymbolicLinksSync());
    });

    test('a command that hangs is stopped, and says so', () async {
      final result = await workspace.run('sleep', ['30'],
          timeout: const Duration(milliseconds: 300));
      expect(result.timedOut, isTrue);
      expect(result.ok, isFalse,
          reason: '"it failed" and "we gave up waiting" lead to different '
              'next moves, so they are different fields');
    });
  });

  group('the tools an agent actually calls', () {
    test('a refused path comes back as a result, not an exception', () async {
      // The agent has to be *told* it was refused so it can choose
      // differently. Throwing would end the turn and leave a stack trace.
      final result =
          await runTool(workspace, 'read_file', {'path': '../../etc/passwd'});
      expect(result.isError, isTrue);
      expect(result.text, contains('outside the workspace'));
    });

    test('an edit that matches nothing says so rather than writing', () async {
      final before = await workspace.readText('README.md');
      final result = await runTool(workspace, 'edit_file',
          {'path': 'README.md', 'old': 'not here', 'new': 'x'});

      expect(result.isError, isTrue);
      expect(await workspace.readText('README.md'), before);
    });

    test('an ambiguous edit refuses rather than picking one', () async {
      // An edit applied to the wrong one of four identical lines is a bug that
      // looks exactly like the model working.
      await workspace.writeText('dup.txt', 'same\nsame\n');
      final result = await runTool(workspace, 'edit_file',
          {'path': 'dup.txt', 'old': 'same', 'new': 'changed'});

      expect(result.isError, isTrue);
      expect(result.text, contains('appears 2 times'));
      expect(await workspace.readText('dup.txt'), 'same\nsame\n');
    });

    test('a unique edit applies and reports what changed', () async {
      final result = await runTool(workspace, 'edit_file',
          {'path': 'README.md', 'old': 'some prose', 'new': 'better prose'});

      expect(result.isError, isFalse);
      expect(result.changedPath, 'README.md');
      expect(await workspace.readText('README.md'), contains('better prose'));
    });

    test('a huge file is truncated with a note, not silently', () async {
      // A model given half a file with no warning edits against the half it
      // saw, and the edit then fails to match for reasons it cannot see.
      await workspace.writeText('big.txt', 'x' * 70000);
      final result = await runTool(workspace, 'read_file', {'path': 'big.txt'});
      expect(result.text, contains('truncated'));
    });

    test('an unknown tool is an error the model can read', () async {
      final result = await runTool(workspace, 'launch_missiles', const {});
      expect(result.isError, isTrue);
    });

    test('a failing command reports as an error', () async {
      final result = await runTool(workspace, 'run',
          {'command': 'false', 'args': const <String>[]});
      expect(result.isError, isTrue);
    });
  });

  test('every tool is in the schema exactly once', () {
    // The schema is what the model is given; a tool missing from it is a tool
    // that exists and can never be called.
    final schemas = toolSchemas(kAgentTools);
    expect(schemas, hasLength(kAgentTools.length));
    expect(schemas.map((s) => s['name']).toSet(), hasLength(kAgentTools.length));
    for (final schema in schemas) {
      expect(schema['input_schema'], isNotNull, reason: '${schema['name']}');
      expect('${schema['description']}'.length, greaterThan(20),
          reason: '${schema['name']} needs a description the model can use');
    }
  });

  test('the workspace arm matches the platform', () {
    expect(localWorkspaceKind, 'io');
  });
}
