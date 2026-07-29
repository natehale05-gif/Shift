import 'package:flutter/material.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';
import 'core/platform/platform_storage.dart';
import 'core/update/update_installer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // An update downloaded during the last session is swapped in here, before
  // any UI exists — a running app cannot replace the directory it is
  // executing from, and doing it at launch means the user never has the app
  // quit out from under them mid-sentence. Never returns if it fires: the
  // process is replaced by the new build.
  if (hasStagedUpdate) {
    if (await applyStagedUpdate()) return;
  }

  // Desktop and Android need to be told where their database lives before the
  // first read; on web this is a no-op (the browser owns IndexedDB).
  await initPersistentStorage();

  runApp(const ShiftAiApp());

  // Hand off from the HTML boot splash only once Flutter has actually painted,
  // so there is no blank frame between the two.
  WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
