import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';
import 'data/api_keys_store.dart';
import 'data/kv_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded before the first frame so the app never renders once as "no keys"
  // and then again with them — which on a slow disk reads as the keys having
  // been forgotten.
  final keys = ApiKeysStore(KvStore());
  await keys.load();

  runApp(ShiftApp(keys: keys));

  // After the first real frame, not before: the HTML splash is what the user
  // is looking at until then, and taking it down early trades a branded screen
  // for a blank one.
  SchedulerBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
