import 'package:flutter/material.dart';

enum AppThemeId { night, day, terminal }

extension AppThemeIdLabel on AppThemeId {
  /// Human-readable name shown in tooltips / theme pickers.
  String get label => switch (this) {
    AppThemeId.night => 'Gece (Tokyo Night)',
    AppThemeId.day => 'Gündüz (Açık)',
    AppThemeId.terminal => 'Terminal (Yeşil)',
  };
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg, surface, surface2, elevated, border, borderStrong;
  final Color text, textMuted, textDim;
  final Color accent, accentSoft, accent2;
  final Color green, red, yellow, cyan, termBg;

  /// Warning / in-progress accent (ADR 0032 D8). Drives the connecting +
  /// authenticating status color and the host-key-changed warning weight.
  /// Distinct from [green] (connected), [red] (error) and [yellow] (legacy
  /// generic accent) so the connecting state is never gray and never confused
  /// with success/error.
  final Color amber;

  // --- Interaction-state tokens (ADR 0040 D2) -----------------------------
  // The state layers + focus indicator the shared primitives (Pressable,
  // buttons, AppToggle, AppTextField) draw from. Derived from the existing
  // accent / accentSoft roles so no new color FAMILY is invented (ADR 0009).

  /// ~7% accent wash drawn under a control on POINTER hover (matches the shell
  /// row's `accent.withValues(alpha: 0.07)`).
  final Color hoverOverlay;

  /// ~14% accent wash drawn while a control is PRESSED (matches the shell row's
  /// `accent.withValues(alpha: 0.14)`); deliberately stronger than
  /// [hoverOverlay] so the state hierarchy reads.
  final Color pressedOverlay;

  /// Dedicated keyboard/AT focus ring color. Accent-based but a DEDICATED role
  /// (never reuse accent TEXT for the ring): verified ≥3:1 against the adjacent
  /// surface/surface2 in all three themes (incl. the light day theme).
  final Color focusRing;

  /// Selected-row background — an alias of [accentSoft] (the exact value the
  /// shell sidebar row already uses for its selected fill), so a selected
  /// control is pixel-identical to a selected sidebar row.
  final Color selectedBg;

  /// Named disabled foreground (carries the ~0.5 disabled intent) so primitives
  /// stop hard-coding `Opacity(0.5)` literals.
  final Color disabledFg;

  /// High-contrast mark drawn ON an accent fill — today the AppToggle knob
  /// (white). Tokenized so the shared widgets carry no raw `Colors.white`.
  final Color onAccent;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.elevated,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.accent,
    required this.accentSoft,
    required this.accent2,
    required this.green,
    required this.red,
    required this.yellow,
    required this.cyan,
    required this.termBg,
    required this.amber,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.focusRing,
    required this.selectedBg,
    required this.disabledFg,
    required this.onAccent,
  });

  static const night = AppColors(
    bg: Color(0xFF16161E),
    surface: Color(0xFF1A1B26),
    surface2: Color(0xFF1F2335),
    elevated: Color(0xFF24283B),
    border: Color(0xFF2A2E42),
    borderStrong: Color(0xFF3B4261),
    text: Color(0xFFC0CAF5),
    textMuted: Color(0xFF7C83A8),
    textDim: Color(0xFF565F89),
    accent: Color(0xFF7AA2F7),
    accentSoft: Color(0x247AA2F7),
    accent2: Color(0xFFBB9AF7),
    green: Color(0xFF9ECE6A),
    red: Color(0xFFF7768E),
    yellow: Color(0xFFE0AF68),
    cyan: Color(0xFF2AC3DE),
    termBg: Color(0xFF16161E),
    amber: Color(0xFFFF9E64),
    // accent 0x7AA2F7 at ~7% / ~14% (matches the shell row hover/pressed).
    hoverOverlay: Color(0x127AA2F7),
    pressedOverlay: Color(0x247AA2F7),
    focusRing: Color(0xFF7AA2F7),
    selectedBg: Color(0x247AA2F7), // == accentSoft
    disabledFg: Color(0xFF7C83A8), // == textMuted
    onAccent: Color(0xFFFFFFFF),
  );

  static const day = AppColors(
    bg: Color(0xFFD6D8DF),
    surface: Color(0xFFE6E7ED),
    surface2: Color(0xFFF4F5F8),
    elevated: Color(0xFFFFFFFF),
    border: Color(0xFFC4C8D4),
    borderStrong: Color(0xFFAEB3C4),
    text: Color(0xFF2C3046),
    textMuted: Color(0xFF5A6589),
    textDim: Color(0xFF8990B3),
    accent: Color(0xFF2E7DE9),
    accentSoft: Color(0x1F2E7DE9),
    accent2: Color(0xFF9854F1),
    green: Color(0xFF587539),
    red: Color(0xFFF52A65),
    yellow: Color(0xFF8C6C3E),
    cyan: Color(0xFF007197),
    termBg: Color(0xFF1A1B26),
    amber: Color(0xFFB15C00),
    // accent 0x2E7DE9 at ~7% / ~14%. accentSoft is 0x1F2E7DE9 here.
    hoverOverlay: Color(0x122E7DE9),
    pressedOverlay: Color(0x242E7DE9),
    focusRing: Color(0xFF2E7DE9),
    selectedBg: Color(0x1F2E7DE9), // == accentSoft
    disabledFg: Color(0xFF5A6589), // == textMuted
    onAccent: Color(0xFFFFFFFF),
  );

  static const terminal = AppColors(
    bg: Color(0xFF0A0D0B),
    surface: Color(0xFF0D1310),
    surface2: Color(0xFF111A14),
    elevated: Color(0xFF16211A),
    border: Color(0xFF1C2B22),
    borderStrong: Color(0xFF2B4234),
    text: Color(0xFFCDE6D4),
    textMuted: Color(0xFF6F9079),
    textDim: Color(0xFF4A6354),
    accent: Color(0xFF3FB950),
    accentSoft: Color(0x243FB950),
    accent2: Color(0xFF56D364),
    green: Color(0xFF3FB950),
    red: Color(0xFFFF6B6B),
    yellow: Color(0xFFD4A72C),
    cyan: Color(0xFF39C5CF),
    termBg: Color(0xFF0A0D0B),
    amber: Color(0xFFE3A21A),
    // accent 0x3FB950 at ~7% / ~14%. accentSoft is 0x243FB950 here.
    hoverOverlay: Color(0x123FB950),
    pressedOverlay: Color(0x243FB950),
    focusRing: Color(0xFF3FB950),
    selectedBg: Color(0x243FB950), // == accentSoft
    disabledFg: Color(0xFF6F9079), // == textMuted
    onAccent: Color(0xFFFFFFFF),
  );

  static AppColors of(AppThemeId id) => switch (id) {
    AppThemeId.night => night,
    AppThemeId.day => day,
    AppThemeId.terminal => terminal,
  };

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? elevated,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textMuted,
    Color? textDim,
    Color? accent,
    Color? accentSoft,
    Color? accent2,
    Color? green,
    Color? red,
    Color? yellow,
    Color? cyan,
    Color? termBg,
    Color? amber,
    Color? hoverOverlay,
    Color? pressedOverlay,
    Color? focusRing,
    Color? selectedBg,
    Color? disabledFg,
    Color? onAccent,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      elevated: elevated ?? this.elevated,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textDim: textDim ?? this.textDim,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accent2: accent2 ?? this.accent2,
      green: green ?? this.green,
      red: red ?? this.red,
      yellow: yellow ?? this.yellow,
      cyan: cyan ?? this.cyan,
      termBg: termBg ?? this.termBg,
      amber: amber ?? this.amber,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      pressedOverlay: pressedOverlay ?? this.pressedOverlay,
      focusRing: focusRing ?? this.focusRing,
      selectedBg: selectedBg ?? this.selectedBg,
      disabledFg: disabledFg ?? this.disabledFg,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      elevated: l(elevated, other.elevated),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textDim: l(textDim, other.textDim),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      accent2: l(accent2, other.accent2),
      green: l(green, other.green),
      red: l(red, other.red),
      yellow: l(yellow, other.yellow),
      cyan: l(cyan, other.cyan),
      termBg: l(termBg, other.termBg),
      amber: l(amber, other.amber),
      hoverOverlay: l(hoverOverlay, other.hoverOverlay),
      pressedOverlay: l(pressedOverlay, other.pressedOverlay),
      focusRing: l(focusRing, other.focusRing),
      selectedBg: l(selectedBg, other.selectedBg),
      disabledFg: l(disabledFg, other.disabledFg),
      onAccent: l(onAccent, other.onAccent),
    );
  }
}
