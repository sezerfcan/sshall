import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import 'shell_state.dart';

/// Actions available from a tab's right-click context menu (ADR 0018 / 0036).
enum TabAction {
  rename,
  close,
  closeOthers,
  closeToRight,
  closeAll,
  pin,
  unpin,
  splitRight,
  unsplit,
  moveToOtherGroup,
  detachToWindow,
  reopenClosed,
  reconnect,
}

/// Show the VS Code-style tab context menu at [position] (global). Returns the
/// chosen action, or null if dismissed. Items that don't apply are disabled.
Future<TabAction?> showTabContextMenu(
  BuildContext context,
  Offset position, {
  required ShellTab tab,
  required bool canReopen,
  required bool canSplit,
  bool canMerge = false,
  bool canDetach = false,
  bool canReconnect = false,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  // Only terminals can be detached into a separate OS window (ADR 0020). Every
  // session tab is closable/pinnable now that management surfaces left the strip
  // (ADR 0022).
  final detachable = canDetach && tab.kind == TabKind.terminal;

  return showMenu<TabAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: [
      // Manual reconnect (ADR 0032 D5): re-runs connect on the SAME tab. Only
      // offered for terminal sessions that carry a stored reconnect thunk.
      if (tab.kind == TabKind.terminal) ...[
        _item(
          context,
          TabAction.reconnect,
          'Yeniden Bağlan',
          '',
          enabled: canReconnect,
        ),
        const PopupMenuDivider(),
      ],
      // Per-tab rename (ADR 0036 D2) — also reachable by double-clicking the
      // pill title. Always available.
      _item(context, TabAction.rename, 'Yeniden Adlandır', ''),
      const PopupMenuDivider(),
      _item(context, TabAction.close, 'Kapat', '⌘W'),
      _item(context, TabAction.closeOthers, 'Diğerlerini Kapat', ''),
      _item(context, TabAction.closeToRight, 'Sağdakileri Kapat', ''),
      _item(context, TabAction.closeAll, 'Tümünü Kapat', ''),
      const PopupMenuDivider(),
      if (tab.pinned)
        _item(context, TabAction.unpin, 'Sabitlemeyi Kaldır', '')
      else
        _item(context, TabAction.pin, 'Sabitle', ''),
      const PopupMenuDivider(),
      _item(
        context,
        TabAction.splitRight,
        'Sağa Böl',
        '⌘\\',
        enabled: canSplit,
      ),
      // Merge / unsplit (ADR 0036 D6): surfaces the previously dead
      // TabsController.unsplit(). Enabled only when a split actually exists.
      _item(context, TabAction.unsplit, 'Birleştir', '⌘⇧\\', enabled: canMerge),
      _item(context, TabAction.moveToOtherGroup, 'Diğer Gruba Taşı', ''),
      if (detachable)
        _item(context, TabAction.detachToWindow, 'Ayrı Pencereye Taşı', ''),
      const PopupMenuDivider(),
      _item(
        context,
        TabAction.reopenClosed,
        'Kapatılan Sekmeyi Geri Aç',
        '⌘⇧T',
        enabled: canReopen,
      ),
    ],
  );
}

PopupMenuItem<TabAction> _item(
  BuildContext context,
  TabAction value,
  String label,
  String shortcut, {
  bool enabled = true,
}) {
  final c = context.c;
  return PopupMenuItem<TabAction>(
    value: value,
    enabled: enabled,
    height: 36,
    child: Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(size: 12.5, color: enabled ? c.text : c.textDim),
          ),
        ),
        if (shortcut.isNotEmpty) ...[
          const SizedBox(width: 24),
          Text(shortcut, style: context.mono(size: 11, color: c.textDim)),
        ],
      ],
    ),
  );
}
