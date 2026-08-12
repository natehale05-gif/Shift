import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'workspace.dart';

/// Which implementation this build got. A test asserts it, because choosing
/// wrong raises nothing — the local arm simply would not exist.
const String localWorkspaceKind = 'io';

/// A real folder on this machine.
///
/// Desktop only, and that is a product decision rather than a limitation: a
/// phone has no folder to point at, so the phone's workspaces are the ones the
/// server holds.
///
/// **Containment is enforced here and nowhere else.** Every method resolves its
/// argument through [_within], which normalises the path and refuses anything
/// that lands outside the root — including via `..`, an absolute path, or a
/// symlink pointing out of the tree. A model deciding what to open is exactly
/// the caller you cannot trust to check first.
class LocalWorkspace implements AgentWorkspace {
  @override
  final String root;

  LocalWorkspace(String root) : root = p.normalize(p.absolute(root));

  /// Resolves [relative] inside the root, or throws.
  ///
  /// Symlinks are resolved before the check. Without that, a link inside the
  /// workspace pointing at `/etc` would pass a purely textual test and then
  /// read whatever it pointed at — which is the whole trick.
  String _within(String relative) {
    final joined = p.normalize(p.join(root, relative));
    final real = _resolveLinks(joined);
    if (real != root && !p.isWithin(root, real)) {
      throw OutsideWorkspace(relative);
    }
    return joined;
  }

  /// The path with any existing symlinks followed. A path that does not exist
  /// yet — a file about to be written — cannot be resolved, so its *parent* is
  /// checked instead, which is what actually decides where the write lands.
  String _resolveLinks(String path) {
    var candidate = path;
    while (true) {
      if (FileSystemEntity.isLinkSync(candidate) ||
          File(candidate).existsSync() ||
          Directory(candidate).existsSync()) {
        try {
          return p.normalize(File(candidate).resolveSymbolicLinksSync());
        } catch (_) {
          return p.normalize(candidate);
        }
      }
      final parent = p.dirname(candidate);
      if (parent == candidate) return p.normalize(path);
      candidate = parent;
    }
  }

  String _relative(String absolute) =>
      p.relative(absolute, from: root).replaceAll(r'\', '/');

  @override
  Future<List<WorkspaceEntry>> list(String directory) async {
    final dir = Directory(_within(directory));
    if (!await dir.exists()) return [];

    final entries = <WorkspaceEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final stat = await entity.stat();
      entries.add(WorkspaceEntry(
        path: _relative(entity.path),
        isDirectory: stat.type == FileSystemEntityType.directory,
        bytes: stat.type == FileSystemEntityType.file ? stat.size : 0,
      ));
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  @override
  Future<String> readText(String path) => File(_within(path)).readAsString();

  @override
  Future<Uint8List> readBytes(String path) => File(_within(path)).readAsBytes();

  @override
  Future<void> writeText(String path, String contents) async {
    final file = File(_within(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final file = File(_within(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    final resolved = _within(path);
    // Refusing to delete the root itself is not paranoia: `delete('.')` is a
    // plausible thing for a model to emit and it would take the repository.
    if (p.normalize(resolved) == root) throw const OutsideWorkspace('.');

    final file = File(resolved);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final dir = Directory(resolved);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<List<String>> glob(String pattern) async {
    final matcher = _globToRegExp(pattern);
    final out = <String>[];
    await for (final entity
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = _relative(entity.path);
      if (_ignored(relative)) continue;
      if (matcher.hasMatch(relative)) out.add(relative);
    }
    out.sort();
    return out;
  }

  @override
  Future<List<GrepHit>> grep(String pattern, {String? inGlob}) async {
    final regexp = RegExp(pattern);
    final files = inGlob == null ? await glob('**') : await glob(inGlob);

    final hits = <GrepHit>[];
    for (final relative in files) {
      String text;
      try {
        text = await File(p.join(root, relative)).readAsString();
      } catch (_) {
        // Binary, or unreadable. Skipped rather than fatal — a repository is
        // full of files that are not text and none of them is an error.
        continue;
      }
      final lines = const LineSplitter().convert(text);
      for (var i = 0; i < lines.length; i++) {
        if (regexp.hasMatch(lines[i])) {
          hits.add(GrepHit(path: relative, line: i + 1, text: lines[i]));
        }
      }
    }
    return hits;
  }

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: root,
      runInShell: false,
    );

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final collecting = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(stdout.write),
      process.stderr.transform(utf8.decoder).forEach(stderr.write),
    ]);

    try {
      final code = await process.exitCode.timeout(timeout);
      await collecting;
      return CommandResult(
        exitCode: code,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      );
    } catch (_) {
      // Killed rather than left running: an agent's command that hangs would
      // otherwise outlive the turn that started it.
      process.kill(ProcessSignal.sigkill);
      return CommandResult(
        exitCode: -1,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
        timedOut: true,
      );
    }
  }

  /// Directories no agent should be reading through, and every one of them is
  /// a real cost rather than tidiness: `.git` is enormous and binary,
  /// `node_modules` is enormous and not yours, and `build` is output.
  static bool _ignored(String relative) {
    for (final part in relative.split('/')) {
      if (const {'.git', 'node_modules', 'build', '.dart_tool'}
          .contains(part)) {
        return true;
      }
    }
    return false;
  }

  /// `**` crosses directories, `*` does not, `?` is one character. Written out
  /// rather than pulled in, because a glob package for three constructs is a
  /// dependency to keep for a decade.
  static RegExp _globToRegExp(String pattern) {
    final out = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          out.write('.*');
          i++;
          // `**/` should also match zero directories, so `**/*.dart` finds a
          // file at the root as well as a nested one.
          if (i + 1 < pattern.length && pattern[i + 1] == '/') i++;
        } else {
          out.write('[^/]*');
        }
      } else if (ch == '?') {
        out.write('[^/]');
      } else {
        out.write(RegExp.escape(ch));
      }
    }
    out.write(r'$');
    return RegExp(out.toString());
  }
}
