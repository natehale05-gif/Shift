import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'shell/app_shell.dart';
import 'shell/shell_controller.dart';

class ShiftApp extends StatelessWidget {
  const ShiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShellController()),
      ],
      child: MaterialApp(
        title: 'SHIFT AI',
        debugShowCheckedModeBanner: false,
        theme: shiftTheme(Brightness.light, defaultTargetPlatform),
        darkTheme: shiftTheme(Brightness.dark, defaultTargetPlatform),

        // Follow the system until there is a setting to override it. Both
        // themes are built to the same standard, so neither is a fallback.
        themeMode: ThemeMode.system,

        home: const AppShell(),
      ),
    );
  }
}
