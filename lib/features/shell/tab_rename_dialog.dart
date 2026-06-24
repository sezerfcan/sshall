import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/context_ext.dart';

/// A small "rename tab" dialog (ADR 0036 D2). Used by the context-menu
/// "Yeniden Adlandır" action so rename works even for pinned / icon-only tabs
/// that have no inline title to double-click. Returns the new title on confirm
/// (an empty string clears the manual title back to the derived default), or
/// null if cancelled. The pill's double-click editor is the primary path; this
/// is the discoverable, always-reachable fallback.
Future<String?> showTabRenameDialog(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TabRenameDialog(initial: current),
  );
}

class _TabRenameDialog extends StatefulWidget {
  const _TabRenameDialog({required this.initial});
  final String initial;

  @override
  State<_TabRenameDialog> createState() => _TabRenameDialogState();
}

class _TabRenameDialogState extends State<_TabRenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() => Navigator.of(context).pop(_controller.text);
  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sekmeyi Yeniden Adlandır',
                style: context.ui(size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Boş bırakırsanız otomatik (host) başlığa döner.',
                style: context.ui(size: 11.5, color: c.textDim),
              ),
              const SizedBox(height: 16),
              CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): _cancel,
                },
                child: TextField(
                  key: const Key('tabRenameField'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  style: context.ui(size: 13, color: c.text),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Sekme başlığı',
                    hintStyle: context.ui(size: 13, color: c.textDim),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('tabRenameCancel'),
                    onPressed: _cancel,
                    child: Text(
                      'İptal',
                      style: context.ui(size: 13, color: c.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('tabRenameConfirm'),
                    onPressed: _commit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.bg,
                    ),
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
