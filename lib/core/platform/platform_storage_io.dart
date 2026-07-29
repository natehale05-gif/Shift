import 'package:path_provider/path_provider.dart';

import '../../data/persistence/storage/idb_factory_io.dart';

/// Roots the sembast database in the OS's per-app support directory, so a
/// downloaded app keeps its chats, projects and keys across restarts.
Future<void> initPersistentStorage() async {
  final dir = await getApplicationSupportDirectory();
  usePersistentStorage(dir.path);
}
