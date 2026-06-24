import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';
import '../settings/app_settings.dart';
import 'shell_state.dart';

/// Close [tabId], prompting first when it is a LIVE session AND the
/// confirm-before-close setting is on (ADR 0038 D7). When the setting is off, or
/// the tab is not a live session, it closes immediately — the previous behavior,
/// so nothing regresses. The single close chokepoint shared by the tab menu,
/// the close button / middle-click and the ⌘W shortcut.
Future<void> closeTabWithConfirm(
  BuildContext context,
  WidgetRef ref,
  String tabId,
) async {
  final tabs = ref.read(tabsControllerProvider.notifier);
  final confirmEnabled = ref
      .read(appSettingsControllerProvider)
      .confirmOnCloseLiveSession;

  if (confirmEnabled && tabs.isLiveSession(tabId)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.c;
        return AlertDialog(
          backgroundColor: c.elevated,
          title: Text(
            'Oturumu kapat?',
            style: ctx.ui(size: 16, weight: FontWeight.w600),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              'Bu sekme canlı bir oturuma bağlı. Kapatırsanız bağlantı sonlanır.',
              style: ctx.ui(size: 13, color: c.textMuted),
            ),
          ),
          actions: [
            GhostButton(
              label: 'Vazgeç',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            DangerButton(
              key: const Key('confirmCloseTab'),
              label: 'Kapat',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
  }
  tabs.close(tabId);
}
