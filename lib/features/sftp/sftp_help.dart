import 'package:flutter/material.dart';
import '../../theme/context_ext.dart';

/// Short, self-explanatory help for the SFTP screen. Opened
/// from the help icon in the SFTP header. Lists the non-obvious interactions:
/// breadcrumb navigation, sortable columns, multi-select, double-click activate,
/// drag-to-transfer, and the transfer queue's distinct cancel vs dismiss.
Future<void> showSftpHelpDialog(BuildContext context) {
  final c = context.c;
  Widget item(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.ui(size: 13, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: context.ui(size: 12, color: c.textMuted)),
            ],
          ),
        ),
      ],
    ),
  );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('SFTP yardımı'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                Icons.alt_route,
                'Yol çubuğu (breadcrumb)',
                'Bir üst klasör adına tıklayarak oraya git. Kalem ikonuyla ham '
                    'yolu yazıp Enter ile geç.',
              ),
              item(
                Icons.swap_vert,
                'Sütun sıralama',
                'Ad / Boyut / Değiştirilme / İzinler başlığına tıkla; tekrar '
                    'tıklayınca yön değişir.',
              ),
              item(
                Icons.checklist,
                'Çoklu seçim',
                'Tek tık seçer; Shift-tık aralık seçer; Cmd/Ctrl-tık ekler veya '
                    'çıkarır.',
              ),
              item(
                Icons.mouse,
                'Çift tık',
                'Klasörü açar, dosyayı diğer panele aktarır.',
              ),
              item(
                Icons.drag_indicator,
                'Sürükle-bırak',
                'Bir seçimi diğer panele ya da bir klasör satırına sürükleyerek '
                    'aktar (yön otomatik).',
              ),
              item(
                Icons.sync_alt,
                'Aktarım kuyruğu',
                'Devam edeni durdurmak için durdur (⊘) düğmesi; biteni listeden '
                    'kaldırmak için kapat (×). Başarısız aktarımı "Yeniden dene" '
                    'ile tekrar başlat.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Anladım'),
        ),
      ],
    ),
  );
}
