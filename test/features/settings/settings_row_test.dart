import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/settings/settings_row.dart';

const _rows = <SettingsRow>[
  SettingsRow(
    id: 'fontSize',
    group: SettingsGroup.terminal,
    label: 'Yazı boyutu',
    description: 'Yeni terminal sekmeleri bu boyutta açılır.',
    keywords: ['font', 'boyut', 'punto'],
  ),
  SettingsRow(
    id: 'port',
    group: SettingsGroup.connection,
    label: 'Varsayılan port',
    description: 'Yeni bağlantıda varsayılan SSH portu.',
    keywords: ['port', '22', 'ssh'],
  ),
  SettingsRow(
    id: 'confirm',
    group: SettingsGroup.behavior,
    label: 'Kapatmadan önce onay iste',
    description: 'Canlı bir oturum sekmesini kapatırken onay sorulur.',
    keywords: ['onay', 'kapat'],
  ),
];

void main() {
  group('filterRows', () {
    test('empty query returns every row', () {
      expect(filterRows(_rows, '').length, _rows.length);
      expect(filterRows(_rows, '   ').length, _rows.length);
    });

    test('matches by label (case-insensitive)', () {
      final r = filterRows(_rows, 'PORT');
      expect(r.length, 1);
      expect(r.single.id, 'port');
    });

    test('matches by description substring', () {
      final r = filterRows(_rows, 'oturum');
      expect(r.length, 1);
      expect(r.single.id, 'confirm');
    });

    test('matches by keyword', () {
      final r = filterRows(_rows, 'punto');
      expect(r.length, 1);
      expect(r.single.id, 'fontSize');
    });

    test('non-matching query drops everything', () {
      expect(filterRows(_rows, 'zzz-nothing'), isEmpty);
    });
  });

  group('SettingsGroup labels', () {
    test('each group has a non-empty canonical label', () {
      for (final g in SettingsGroup.values) {
        expect(g.label.trim().isNotEmpty, isTrue);
      }
    });

    test('labels are the single source (Görünüm / Terminal / Bağlantı …)', () {
      expect(SettingsGroup.appearance.label, 'Görünüm');
      expect(SettingsGroup.terminal.label, 'Terminal');
      expect(SettingsGroup.connection.label, 'Bağlantı');
      expect(SettingsGroup.behavior.label, 'Davranış');
      expect(SettingsGroup.shortcuts.label, 'Klavye Kısayolları');
      expect(SettingsGroup.about.label, 'Hakkında');
    });
  });
}
