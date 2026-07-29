import 'package:flutter/material.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';
import 'core/platform/platform_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop and Android need to be told where their database lives before the
  // first read; on web this is a no-op (the browser owns IndexedDB).
  await initPersistentStorage();

  runApp(const ShiftAiApp());

  // Hand off from the HTML boot splash only once Flutter has actually painted,
  // so there is no blank frame between the two.
  WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
