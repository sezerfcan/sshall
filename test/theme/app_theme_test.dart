import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/theme/app_colors.dart';
import 'package:sshall/theme/app_theme.dart';
import 'package:sshall/theme/context_ext.dart';

void main() {
  testWidgets('theme exposes AppColors via context.c', (tester) async {
    late AppColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: appThemeData(AppThemeId.night),
      home: Builder(builder: (ctx) { seen = ctx.c; return const SizedBox(); }),
    ));
    expect(seen.accent, AppColors.night.accent);
    expect(seen.bg, AppColors.night.bg);
  });

  testWidgets('day theme is light brightness', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: appThemeData(AppThemeId.day), home: const SizedBox()));
    expect(appThemeData(AppThemeId.day).brightness, Brightness.light);
    expect(appThemeData(AppThemeId.night).brightness, Brightness.dark);
  });
}
