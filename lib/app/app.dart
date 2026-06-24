import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shell/app_shell.dart';
import '../features/shell/shell_state.dart';
import '../features/unlock/unlock_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class SshallApp extends ConsumerWidget {
  const SshallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeId = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: 'sshall',
      debugShowCheckedModeBanner: false,
      theme: appThemeData(themeId),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(sessionUnlockedProvider);
    if (unlocked) return const AppShell();
    return UnlockScreen(
      onUnlocked: () =>
          ref.read(sessionUnlockedProvider.notifier).state = true,
    );
  }
}
