import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';
import '../services/persistence_service.dart';

const _uuid = Uuid();

/// Owns the user's projects. The "active" project scopes new conversations
/// and contributes instructions/knowledge to the system prompt.
class ProjectStore extends ChangeNotifier {
  final PersistenceService persistence;

  List<Project> _projects = [];
  String? _activeProjectId;

  ProjectStore({required this.persistence});

  List<Project> get projects => List.unmodifiable(_projects);
  String? get activeProjectId => _activeProjectId;

  Project? get activeProject => projectById(_activeProjectId);

  Project? projectById(String? id) {
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  Future<void> load() async {
    _projects = await persistence.loadProjects();
    final savedActive = await persistence.loadActiveProject();
    // Only restore it if the project still exists.
    if (savedActive != null && projectById(savedActive) != null) {
      _activeProjectId = savedActive;
    }
    notifyListeners();
  }

  Project createProject(String name) {
    final project = Project(
      id: _uuid.v4(),
      name: name,
      colorIndex: _projects.length % Project.colors.length,
    );
    _projects.add(project);
    _activeProjectId = project.id;
    notifyListeners();
    _persist();
    return project;
  }

  void updateProject(Project updated) {
    final index = _projects.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    _projects[index] = updated;
    notifyListeners();
    _persist();
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    if (_activeProjectId == id) {
      _activeProjectId = null;
      persistence.saveActiveProject(null);
    }
    notifyListeners();
    _persist();
  }

  /// Sets which project new conversations belong to (null = none). Persisted
  /// so the selection survives a reload.
  void setActiveProject(String? id) {
    _activeProjectId = id;
    notifyListeners();
    persistence.saveActiveProject(id);
  }

  Future<void> _persist() => persistence.saveProjects(_projects);
}
