/// What an agent is allowed to do, and where.
///
/// One interface with two arms behind it: a real folder on this machine, and
/// (later) a repository the server holds. Every tool above talks to this, so
/// adding the server arm adds an implementation rather than a second agent.
///
/// **Every path is relative to the workspace root, and staying inside it is
/// this type's job, not the caller's.** An agent is a model deciding what to
/// open; if `../../.ssh/id_rsa` were merely discouraged, one confused
/// generation would read it. The check lives at the boundary where it cannot
/// be forgotten.
library;

import 'dart:typed_data';

/// A file or directory, as a listing shows it.
class WorkspaceEntry {
  /// Relative to the workspace root, using `/` on every platform.
  final String path;
  final bool isDirectory;
  final int bytes;

  const WorkspaceEntry({
    required this.path,
    required this.isDirectory,
    this.bytes = 0,
  });
}

/// What a command did.
class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  /// True when the command was stopped for running too long rather than
  /// finishing. Kept separate from a non-zero exit: "it failed" and "we gave up
  /// waiting" lead to different next moves.
  final bool timedOut;

  const CommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
  });

  bool get ok => exitCode == 0 && !timedOut;
}

/// Raised when a tool asks for something outside the workspace.
///
/// An exception rather than a null, because every caller must stop — there is
/// no sensible "carry on without it" for a path that escaped the root.
class OutsideWorkspace implements Exception {
  final String path;

  const OutsideWorkspace(this.path);

  @override
  String toString() => 'Path is outside the workspace: $path';
}

/// The operations an agent has.
///
/// Deliberately small. Everything an agent does to a repository is one of
/// these, which is what makes the loop above it reviewable and what makes a
/// second implementation tractable.
abstract class AgentWorkspace {
  /// Absolute, for display and for a shell's working directory. Never sent to
  /// a model — a home directory in a prompt is an information leak and is of
  /// no use to it.
  String get root;

  Future<List<WorkspaceEntry>> list(String directory);

  Future<String> readText(String path);

  Future<Uint8List> readBytes(String path);

  Future<void> writeText(String path, String contents);

  /// Writes bytes, for the formats that are not text.
  ///
  /// Separate from [writeText] rather than a flag on it, because the two have
  /// different callers: a model writes text, and only the app writes bytes —
  /// there is no tool that hands a model a byte array, and there should not be
  /// one. What the model supplies is Markdown or CSV; the container is built
  /// here.
  Future<void> writeBytes(String path, Uint8List bytes);

  Future<void> delete(String path);

  /// Paths matching a glob, relative to the root.
  Future<List<String>> glob(String pattern);

  /// Files containing [pattern], with the matching lines.
  Future<List<GrepHit>> grep(String pattern, {String? inGlob});

  /// Runs a command **with the workspace as its working directory**.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout,
  });
}

class GrepHit {
  final String path;
  final int line;
  final String text;

  const GrepHit({required this.path, required this.line, required this.text});
}
