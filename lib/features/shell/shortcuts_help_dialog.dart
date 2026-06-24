import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';

/// The canonical (binding, description) keyboard-shortcut list. SINGLE source of
/// truth shared by BOTH this help dialog AND the Settings "Klavye Kısayolları"
/// section (ADR 0038 D8), so the two never drift. macOS glyphs are shown; the
/// help dialog notes the Windows/Linux Ctrl mapping.
const List<(String, String)> kShortcutEntries = <(String, String)>[
  ('⌘W', 'Aktif oturum sekmesini kapat'),
  ('⌘T', 'Yeni sekme (bağlantı evi / karşılama)'),
  ('⌘1 … ⌘4', 'Sol raya atla: Bağlantılar / SFTP / Vault / Ayarlar'),
  ('⌘,', 'Ayarlar panelini aç (Esc ile kapanır)'),
  ('Esc', 'Açık paneli kapat (Ayarlar / Vault)'),
  ('⌘B', 'Kenar çubuğunu (bağlantılar) göster / gizle'),
  ('⌘\\', 'Aktif grubu sağa böl'),
  ('⌘⇧\\', 'Bölmeyi birleştir (tek panele döndür)'),
  ('⌃Tab  /  ⌃⇧Tab', 'Son kullanılan sekmeler arası ileri / geri'),
  ('⌘⇧]  /  ⌘⇧[', 'Sonraki / önceki sekme'),
  ('⌘5 … ⌘9', 'Editör grubuna (split) atla'),
  ('⌘⇧T', 'Kapatılan oturum sekmesini geri aç'),
  ('⌘ +  /  ⌘ −  /  ⌘ 0', 'Terminal yazısını büyüt / küçült / sıfırla'),
];

/// Discoverable reference for every tab shortcut and mouse interaction.
/// Opened from the title bar's keyboard button.
void showShortcutsHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const ShortcutsHelpDialog(),
  );
}

class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static const _keyboard = kShortcutEntries;

  static const _mouse = <(String, String)>[
    ('Tek tık', 'Sekmeyi seç ve grubunu odakla'),
    ('Orta tık', 'Sekmeyi kapat'),
    (
      'Çift tık (başlık)',
      'Sekmeyi yeniden adlandır (Enter: kaydet · Esc: iptal)',
    ),
    ('Çift tık (boş şerit)', 'Bağlantı evine (yeni oturum) git'),
    ('"+" düğmesi', 'Yeni sekme (şerit sonundaki + · ⌘T ile aynı)'),
    ('Böl düğmesi', 'Aktif grubu sağa böl (şerit sonundaki böl simgesi · ⌘\\)'),
    (
      'Sağ tık',
      'Sekme menüsü: yeniden adlandır / kapat / sabitle / böl / birleştir / '
          'taşı / ayrı pencere / geri aç',
    ),
    ('Sürükle', 'Sekmeyi sırala veya başka gruba taşı'),
    ('Gövdeye sürükle', 'Sol/sağ/üst/alt → yönlü böl · orta → bu gruba taşı'),
    (
      'Pencere dışına sürükle',
      'Terminali ayrı bir pencereye kopar (geri almak için: pencerede "Ana Pencereye Al")',
    ),
    ('Ayraç sürükle', 'Panelleri boyutlandır · çift tık: eşitle'),
    ('Başlık çubuğunu sürükle', 'Pencereyi taşı (başlık çubuğunu sürükle)'),
    ('Başlık çubuğuna çift tık', 'Pencereyi büyüt / geri al'),
  ];

  static const _connections = <(String, String)>[
    (
      'Kalem simgesi',
      'Bir host\'u düzenle: host-detail kartındaki kalem simgesine tıkla',
    ),
    (
      'Sağ tık (sidebar)',
      'Bir host\'u düzenle / sil: sidebar\'da host satırına sağ tık → Düzenle / Sil',
    ),
  ];

  static const _docker = <(String, String)>[
    (
      'Local Docker',
      'Sidebar\'daki "Local Docker" düğümü — bu makinedeki container\'lar '
          '(Docker Desktop çalışıyor olmalı).',
    ),
    (
      'Docker olarak işaretle',
      'Host satırı → Düzenle → "Bu sunucu Docker çalıştırıyor" seçeneğini aç.',
    ),
    (
      "Container'ları göster",
      'Sidebar\'da host satırındaki Docker simgesinin yanındaki oku tıklayarak '
          "Containers düğümünü aç.",
    ),
    (
      'Terminal aç',
      "Çalışan bir container'ın yanındaki terminal simgesi `docker exec -it` "
          'ile içeride etkileşimli kabuk açar.',
    ),
    (
      'Durmuş container',
      "Yalnızca çalışan container'lar için terminal açılır; "
          'durmuş bir container açılamaz.',
    ),
    (
      'Dosyalara gözat',
      "Container satırındaki klasör simgesi container dosyalarını "
          'SFTP panelinde açar; `docker cp` ile dosya aktarabilirsin.',
    ),
  ];

  static const _remoteEdit = <(String, String)>[
    (
      'Uzak dosyayı düzenle',
      'Uzak panelde dosyaya ⋯ (Eylemler) → Düzenle → varsayılan editörde açılır.',
    ),
    ('Otomatik geri-yükleme', 'Kaydedince değişiklik otomatik uzağa yüklenir.'),
    (
      'Çakışma tespiti',
      'Uzaktaki dosya bu sırada değiştiyse, ezmeden önce sorar '
          '(Uzağı ez / Farklı kaydet / Devam).',
    ),
    (
      'Düzenlemeyi bitir',
      'Alttaki panelden "Bitir" ile düzenlemeyi kapatırsın (geçici kopya silinir).',
    ),
  ];

  static const _layout = <(String, String)>[
    (
      'Dar pencere',
      'Araç çubuğu küçülür: sürüm yazısı gizlenir, tema + yardım "⋯" menüsüne toplanır',
    ),
    (
      'Dar panel',
      'Sekmeler kısalır, çok darda yalnız ikon kalır (başlık ipucunda)',
    ),
    (
      'Kenar çubuğu',
      'Nav çubuğundaki düğme ya da ⌘B ile gizlenip içeriğe yer açılır',
    ),
    (
      'Şerit = yalnız oturum',
      'Terminal & SFTP sekmedir; Bağlantılar sol kenar + karşılama, '
          'Ayarlar & Vault ise nav çubuğundan açılan panel (overlay)',
    ),
    (
      'Bağlantı evi',
      'Hiç oturum yokken karşılama görünür; nav çubuğundaki "Bağlantılar" '
          'oturumlar açıkken de evi öne getirir (oturumlar canlı kalır)',
    ),
  ];

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
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.keyboard_outlined, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Klavye Kısayolları & Sekme Etkileşimleri',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.ui(size: 15, weight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: Icon(Icons.close, size: 18, color: c.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'macOS gösterilir; Windows/Linux\'ta ⌘ yerine Ctrl (⌃) kullanın.',
                style: context.ui(size: 11.5, color: c.textDim),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section(context, 'Klavye', _keyboard),
                      const SizedBox(height: 16),
                      _section(context, 'Fare', _mouse),
                      const SizedBox(height: 16),
                      _section(context, 'Bağlantı yönetimi', _connections),
                      const SizedBox(height: 16),
                      _section(context, 'Docker', _docker),
                      const SizedBox(height: 16),
                      _section(context, 'Uzak düzenleme', _remoteEdit),
                      const SizedBox(height: 16),
                      _section(context, 'Uyarlanır düzen', _layout),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<(String, String)> rows,
  ) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: context.ui(
            size: 11,
            weight: FontWeight.w700,
            color: c.textMuted,
            spacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        for (final (keys, desc) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    keys,
                    style: context.mono(size: 12, color: c.text),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    desc,
                    style: context.ui(size: 12.5, color: c.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
