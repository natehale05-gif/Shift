import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShiftApp());

  // After the first real frame, not before: the HTML splash is what the user
  // is looking at until then, and taking it down early trades a branded screen
  // for a blank one.
  SchedulerBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
