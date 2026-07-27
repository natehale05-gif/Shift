import 'package:flutter/material.dart';

import 'app.dart';
import 'services/web/boot_splash.dart';

void main() {
  runApp(const ShiftAiApp());

  // Hand off from the HTML boot splash only once Flutter has actually painted,
  // so there is no blank frame between the two.
  WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
