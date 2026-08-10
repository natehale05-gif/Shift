import 'dart:typed_data';

import 'workspace.dart';

/// See the IO copy: a test asserts which arm this build got, because choosing
/// wrong raises nothing.
const String localWorkspaceKind = 'unavailable';

/// In a browser there is no folder to point at.
///
/// This is not a gap to fill later — it is the reason the phone and the web
/// get server-held workspaces instead. Every method says so rather than
/// returning an empty list, because an agent silently finding no files would
/// look like an empty repository and it would then confidently write a new one.
class LocalWorkspace implements AgentWorkspace {
  LocalWorkspace(String root);

  Never _unavailable() => throw UnsupportedError(
        'A local folder is not reachable from a browser. Use a GitHub '
        'workspace here.',
      );

  @override
  String get root => _unavailable();

  @override
  Future<List<WorkspaceEntry>> list(String directory) => _unavailable();

  @override
  Future<String> readText(String path) => _unavailable();

  @override
  Future<Uint8List> readBytes(String path) => _unavailable();

  @override
  Future<void> writeText(String path, String contents) => _unavailable();

  @override
  Future<void> delete(String path) => _unavailable();

  @override
  Future<List<String>> glob(String pattern) => _unavailable();

  @override
  Future<List<GrepHit>> grep(String pattern, {String? inGlob}) =>
      _unavailable();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 2),
  }) =>
      _unavailable();
}
