import 'package:flutter/material.dart';
import '../../data/models/file_mode.dart';
import '../../theme/context_ext.dart';
import '../../widgets/buttons.dart';

Future<int?> showChmodDialog(BuildContext context,
    {required String name, required int mode}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _ChmodDialog(name: name, mode: mode & 0x1FF),
  );
}

class _ChmodDialog extends StatefulWidget {
  final String name;
  final int mode;
  const _ChmodDialog({required this.name, required this.mode});
  @override
  State<_ChmodDialog> createState() => _ChmodDialogState();
}

class _ChmodDialogState extends State<_ChmodDialog> {
  late int _mode = widget.mode;

  // Bit indices come from the shared FileMode source of truth so the dialog and
  // the model never drift on the rwx layout. (Not const: indexing FileMode.bits
  // is not a compile-time constant.)
  static final _rows = [
    ('Sahip', const ['user_r', 'user_w', 'user_x'], FileMode.bits[0]),
    ('Grup', const ['group_r', 'group_w', 'group_x'], FileMode.bits[1]),
    ('Diğer', const ['other_r', 'other_w', 'other_x'], FileMode.bits[2]),
  ];

  void _toggle(int bit) => setState(() => _mode = FileMode.toggle(_mode, bit));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text('İzinler — ${widget.name}',
          style: context.ui(size: 15, weight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Row(
              children: [
                SizedBox(
                    width: 64,
                    child: Text(row.$1,
                        style: context.ui(size: 13, color: c.textMuted))),
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: CheckboxListTile(
                      key: ValueKey('perm_${row.$2[i]}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(const ['r', 'w', 'x'][i]),
                      value: FileMode.has(_mode, row.$3[i]),
                      onChanged: (_) => _toggle(row.$3[i]),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(FileMode.octal(_mode),
              style: context.mono(size: 18, color: c.accent)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal')),
        PrimaryButton(
            label: 'Uygula',
            onPressed: () => Navigator.pop(context, _mode)),
      ],
    );
  }
}
