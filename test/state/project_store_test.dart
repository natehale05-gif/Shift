import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/state/project_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the active project selection is persisted and restored on reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();

    final store = ProjectStore(persistence: persistence);
    await store.load();
    final project = store.createProject('Launch');
    store.setActiveProject(project.id);
    // Give the async persistence writes a moment to flush.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A fresh store over the same persistence restores the selection.
    final reloaded = ProjectStore(persistence: persistence);
    await reloaded.load();
    expect(reloaded.activeProjectId, project.id);
    expect(reloaded.activeProject?.name, 'Launch');
  });

  test('deleting the active project clears the persisted selection', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    final store = ProjectStore(persistence: persistence);
    await store.load();
    final project = store.createProject('Temp');
    store.setActiveProject(project.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    store.deleteProject(project.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final reloaded = ProjectStore(persistence: persistence);
    await reloaded.load();
    expect(reloaded.activeProjectId, isNull);
  });
}
