import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_io.dart';

String? _persistentRoot;

/// Points storage at a real directory. Called once from `main()` on desktop
/// and Android (see `platform_storage_io.dart`).
///
/// Until this is called the factory stays in-memory, which is what
/// `flutter test` wants: a fresh isolated database per [defaultIdbFactory]
/// call, so tests never see each other's data. Tests do not run `main()`, so
/// they never opt in.
void usePersistentStorage(String directoryPath) =>
    _persistentRoot = directoryPath;

/// Returns to the in-memory default. Only tests need this — they configure a
/// temp root and must not leave it set for whatever runs next.
@visibleForTesting
void resetPersistentStorage() => _persistentRoot = null;

/// sembast on disk once a root is configured; in-memory otherwise.
///
/// This used to be unconditionally in-memory, which is why a downloaded app
/// would have forgotten every chat on restart.
IdbFactory defaultIdbFactory() => _persistentRoot == null
    ? newIdbFactoryMemory()
    : getIdbFactorySembastIo(_persistentRoot!);
