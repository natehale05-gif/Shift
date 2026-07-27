import 'package:idb_shim/idb_client_memory.dart';

/// VM fallback (flutter test): a fresh in-memory IndexedDB per call, so
/// each PersistenceService instance in tests is isolated.
IdbFactory defaultIdbFactory() => newIdbFactoryMemory();
