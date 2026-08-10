import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'data/api_keys_store.dart';
import 'features/chat/turn_controller.dart';
import 'shell/app_shell.dart';
import 'shell/shell_controller.dart';

class ShiftApp extends StatelessWidget {
  final ApiKeysStore keys;

  const ShiftApp({super.key, required this.keys});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider.value(value: keys),
        ChangeNotifierProvider(create: (_) => TurnController(keys: keys)),
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
