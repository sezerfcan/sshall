import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/data/models/folder.dart';
import 'package:sshall/features/connect/widgets/folder_combobox.dart';
import 'package:sshall/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.night]),
  home: Scaffold(body: child),
);

Folder _f(String id, String name) => Folder(
  id: id,
  parentId: null,
  name: name,
  username: null,
  port: null,
  authRef: null,
  order: 0,
);

void main() {
  testWidgets('lists Kök + folders and fires onChanged', (tester) async {
    String? changed = '__none__';
    await tester.pumpWidget(
      _wrap(
        FolderCombobox(
          value: null,
          folders: [_f('work', 'work'), _f('home', 'home')],
          onChanged: (v) => changed = v,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('folder')));
    await tester.pumpAndSettle();
    expect(find.text('Kök'), findsWidgets);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('work').last);
    await tester.pumpAndSettle();
    expect(changed, 'work');
  });

  testWidgets('dangling folder ref does not crash; shows missing item', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FolderCombobox(
          value: 'ghost', // not present in the folder list
          folders: [_f('work', 'work')],
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('(eksik klasör — silinmiş)'), findsOneWidget);
  });
}
