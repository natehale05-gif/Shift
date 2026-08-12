import '../agents/permission.dart';

/// Where an agent's work sits.
///
/// Two arms, because the answer differs by device: a desktop can point at a
/// folder on disk, a phone cannot, so the phone's only option is a repository
/// the server has cloned. One type rather than two models, so every surface
/// above renders both without asking which it got.
sealed class Workspace {
  final String id;
  final String name;

  /// What may happen here without asking first.
  ///
  /// A property of the *place*, not of the mode or the run: "don't ask" is a
  /// reasonable thing to say about a scratch folder and an unreasonable thing
  /// to say about everything you own, and someone who decides it once should
  /// not be re-deciding it per task. Defaults to [PermissionMode.ask], which is
  /// also what an unreadable stored value reads as.
  final PermissionMode permission;

  const Workspace({
    required this.id,
    required this.name,
    this.permission = PermissionMode.ask,
  });

  Map<String, dynamic> toJson();

  /// The same workspace, with a different standing answer.
  Workspace withPermission(PermissionMode mode);

  static Workspace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String) return null;
    final permission = PermissionMode.fromName(raw['permission'] as String?);

    return switch (raw['kind']) {
      'local' when raw['path'] is String => LocalFolder(
          id: id,
          name: name,
          path: raw['path'] as String,
          permission: permission,
        ),
      'github' when raw['repo'] is String => GitHubRepo(
          id: id,
          name: name,
          repo: raw['repo'] as String,
          branch: raw['branch'] as String? ?? 'main',
          permission: permission,
        ),
      _ => null,
    };
  }
}

/// A real folder on this machine. Desktop only — there is nothing to point at
/// on a phone, and offering it there would be a control that cannot work.
///
/// Named for what it is rather than `LocalWorkspace`, which is taken: the agent
/// layer's `LocalWorkspace` is the thing that *operates* on this path. Two types
/// with one name, one describing the choice and one doing the work, is a
/// collision a reader has to resolve every time.
class LocalFolder extends Workspace {
  final String path;

  const LocalFolder({
    required super.id,
    required super.name,
    required this.path,
    super.permission,
  });

  @override
  LocalFolder withPermission(PermissionMode mode) =>
      LocalFolder(id: id, name: name, path: path, permission: mode);

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'local',
        'id': id,
        'name': name,
        'path': path,
        'permission': permission.name,
      };
}

/// A repository the server holds. Every device, and the phone's only option.
class GitHubRepo extends Workspace {
  final String repo;
  final String branch;

  const GitHubRepo({
    required super.id,
    required super.name,
    required this.repo,
    this.branch = 'main',
    super.permission,
  });

  @override
  GitHubRepo withPermission(PermissionMode mode) => GitHubRepo(
      id: id, name: name, repo: repo, branch: branch, permission: mode);

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'github',
        'id': id,
        'name': name,
        'repo': repo,
        'branch': branch,
        'permission': permission.name,
      };
}

/// What an agent is doing, and therefore where it is listed.
///
/// The order is the order the Inbox reads in, which is not alphabetical and is
/// not arbitrary: the things asking something of you come first.
enum AgentStatus {
  /// Finished, and waiting on a person — a question, or a result to look at.
  needsAttention,

  /// Running right now.
  working,

  /// Its change is up for review.
  inReview,

  /// A pull request is open.
  openPr,

  /// Seen and done with.
  read,

  /// It stopped without finishing.
  failed;

  String get label => switch (this) {
        AgentStatus.needsAttention => 'Needs Attention',
        AgentStatus.working => 'Working',
        AgentStatus.inReview => 'In Review',
        AgentStatus.openPr => 'Open PR',
        AgentStatus.read => 'Read',
        AgentStatus.failed => 'Failed',
      };

  static AgentStatus fromName(String name) => AgentStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => AgentStatus.read,
      );
}

/// Lines added and removed. Shown on nearly every row, so it is a value rather
/// than two loose ints that a caller could format four different ways.
class DiffStat {
  final int added;
  final int removed;

  const DiffStat({this.added = 0, this.removed = 0});

  bool get isEmpty => added == 0 && removed == 0;

  /// `+8,807 -22`, grouped, because a six-figure diff read without separators
  /// is a number nobody can size at a glance.
  @override
  String toString() => '+${_grouped(added)} -${_grouped(removed)}';

  static String _grouped(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  Map<String, dynamic> toJson() => {'added': added, 'removed': removed};

  static DiffStat fromJson(Object? raw) => raw is Map
      ? DiffStat(
          added: raw['added'] as int? ?? 0,
          removed: raw['removed'] as int? ?? 0,
        )
      : const DiffStat();
}

/// One task, and the unit the whole mode is built around.
class Agent {
  final String id;
  final String title;
  final String workspaceId;
  final AgentStatus status;
  final DiffStat diff;

  /// Null when nothing has run checks yet. Distinguished from `false` on
  /// purpose: "not checked" and "checks failed" are different things and a
  /// green tick for the first would be a lie.
  final bool? checksPassed;

  /// What it is waiting on or what went wrong — the second line of a row, when
  /// there is something to say beyond the numbers.
  final String? note;

  final DateTime updatedAt;

  const Agent({
    required this.id,
    required this.title,
    required this.workspaceId,
    required this.status,
    this.diff = const DiffStat(),
    this.checksPassed,
    this.note,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'workspaceId': workspaceId,
        'status': status.name,
        'diff': diff.toJson(),
        if (checksPassed != null) 'checksPassed': checksPassed,
        if (note != null) 'note': note,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Agent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final workspaceId = raw['workspaceId'];
    final updated = DateTime.tryParse('${raw['updatedAt']}');
    if (id is! String ||
        title is! String ||
        workspaceId is! String ||
        updated == null) {
      return null;
    }

    return Agent(
      id: id,
      title: title,
      workspaceId: workspaceId,
      status: AgentStatus.fromName('${raw['status']}'),
      diff: DiffStat.fromJson(raw['diff']),
      checksPassed: raw['checksPassed'] as bool?,
      note: raw['note'] as String?,
      updatedAt: updated,
    );
  }
}
