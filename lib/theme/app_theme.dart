import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData appThemeData(AppThemeId id) {
  final c = AppColors.of(id);
  final brightness = id == AppThemeId.day ? Brightness.light : Brightness.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness, primary: c.accent, surface: c.surface,
      onSurface: c.text, error: c.red,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'IBM Plex Sans', bodyColor: c.text, displayColor: c.text),
    iconTheme: IconThemeData(color: c.textMuted),
    dialogTheme: DialogThemeData(backgroundColor: c.elevated),
    splashFactory: NoSplash.splashFactory,
  );
}
