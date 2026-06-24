import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/vault/identity_filter.dart';
import 'package:sshall/features/vault/vault_search_bar.dart';
import 'package:sshall/theme/app_colors.dart';

void main() {
  testWidgets('typing fires onQueryChanged', (tester) async {
    String? q;
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: VaultSearchBar(
            controller: controller,
            typeFilter: IdentityTypeFilter.all,
            unusedOnly: false,
            onQueryChanged: (v) => q = v,
            onTypeChanged: (_) {},
            onUnusedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('vaultSearch')), 'web');
    expect(q, 'web');
  });

  testWidgets('tapping a segment fires onTypeChanged', (tester) async {
    IdentityTypeFilter? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: VaultSearchBar(
            controller: TextEditingController(),
            typeFilter: IdentityTypeFilter.all,
            unusedOnly: false,
            onQueryChanged: (_) {},
            onTypeChanged: (f) => picked = f,
            onUnusedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Anahtarlar'));
    expect(picked, IdentityTypeFilter.keys);
  });

  testWidgets('toggling "Kullanılmayanlar" fires onUnusedChanged', (
    tester,
  ) async {
    bool? toggled;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.night]),
        home: Scaffold(
          body: VaultSearchBar(
            controller: TextEditingController(),
            typeFilter: IdentityTypeFilter.all,
            unusedOnly: false,
            onQueryChanged: (_) {},
            onTypeChanged: (_) {},
            onUnusedChanged: (v) => toggled = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kullanılmayanlar'));
    expect(toggled, isTrue);
  });
}
