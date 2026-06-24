import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_controller.dart';
import '../terminal/terminal_session_controller.dart';

/// What surface the app shows when it launches (Behavior group, D7).
enum OpenOnLaunch {
  /// Always land on the connection home / welcome surface.
  welcome,

  /// Try to restore the last surface (kept simple in pass-1; deep
  /// restore-sessions is pass-2).
  last,
}

extension OpenOnLaunchLabel on OpenOnLaunch {
  /// Human-readable Turkish label shown in the dropdown.
  String get label => switch (this) {
    OpenOnLaunch.welcome => 'Karşılama',
    OpenOnLaunch.last => 'Son durum',
  };
}

/// Curated monospace families offered for the terminal (D5). JetBrains Mono is
/// the bundled default (ADR 0009 fonts); the rest are common platform monospace
/// faces that xterm renders without bundling. The list is the single source for
/// the font-family dropdown and for validating a persisted value.
const List<String> kMonospaceFamilies = <String>[
  'JetBrains Mono',
  'IBM Plex Mono',
  'Menlo',
  'Monaco',
  'Courier New',
  'Consolas',
  'SF Mono',
  'Fira Code',
];

/// Default terminal font family — the bundled face (ADR 0009).
const String kDefaultFontFamily = 'JetBrains Mono';

/// Default SSH port pre-filled by the connect dialog (D6). Kept backward
/// compatible: when no setting is stored the connect dialog still defaults to
/// 22.
const int kDefaultPort = 22;

/// Min/max for the persisted default port (an integer TCP port).
const int kPortMin = 1;
const int kPortMax = 65535;

/// Max keepalive interval (seconds). 0 = disabled.
const int kKeepAliveMax = 3600;

/// Immutable bag of every user preference managed by the settings surface
/// (ADR 0038 D3). sharedPrefs-backed via [AppSettingsController], following the
/// `SidebarController` pattern (ADR 0030). Field-granular [copyWith] keeps each
/// setter cheap and pure.
class AppSettings {
  /// Global default terminal font size; new tabs initialise from this instead
  /// of the hard-coded [kFontDefault] (D5). Clamped to [kFontMin, kFontMax].
  final int terminalFontSize;

  /// Global terminal font family read by the terminal + detached window (D5).
  /// Always one of [kMonospaceFamilies].
  final String terminalFontFamily;

  /// Pre-filled username on the connect form (D6). Empty = no default.
  final String defaultUsername;

  /// Pre-filled SSH port on the connect form (D6). Defaults to [kDefaultPort].
  final int defaultPort;

  /// Keepalive interval in seconds (D6). 0 = disabled.
  final int keepAliveSeconds;

  /// When true, closing a connected/live session tab prompts for confirmation
  /// (D7). Wired into the tab-close path.
  final bool confirmOnCloseLiveSession;

  /// What surface to show on launch (D7).
  final OpenOnLaunch openOnLaunch;

  const AppSettings({
    this.terminalFontSize = 13,
    this.terminalFontFamily = kDefaultFontFamily,
    this.defaultUsername = '',
    this.defaultPort = kDefaultPort,
    this.keepAliveSeconds = 0,
    this.confirmOnCloseLiveSession = true,
    this.openOnLaunch = OpenOnLaunch.welcome,
  });

  /// The defaults every field falls back to (also the reset target).
  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    int? terminalFontSize,
    String? terminalFontFamily,
    String? defaultUsername,
    int? defaultPort,
    int? keepAliveSeconds,
    bool? confirmOnCloseLiveSession,
    OpenOnLaunch? openOnLaunch,
  }) => AppSettings(
    terminalFontSize: terminalFontSize ?? this.terminalFontSize,
    terminalFontFamily: terminalFontFamily ?? this.terminalFontFamily,
    defaultUsername: defaultUsername ?? this.defaultUsername,
    defaultPort: defaultPort ?? this.defaultPort,
    keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
    confirmOnCloseLiveSession:
        confirmOnCloseLiveSession ?? this.confirmOnCloseLiveSession,
    openOnLaunch: openOnLaunch ?? this.openOnLaunch,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.terminalFontSize == terminalFontSize &&
      other.terminalFontFamily == terminalFontFamily &&
      other.defaultUsername == defaultUsername &&
      other.defaultPort == defaultPort &&
      other.keepAliveSeconds == keepAliveSeconds &&
      other.confirmOnCloseLiveSession == confirmOnCloseLiveSession &&
      other.openOnLaunch == openOnLaunch;

  @override
  int get hashCode => Object.hash(
    terminalFontSize,
    terminalFontFamily,
    defaultUsername,
    defaultPort,
    keepAliveSeconds,
    confirmOnCloseLiveSession,
    openOnLaunch,
  );
}

/// Holds [AppSettings] and persists changes to SharedPreferences — the generic
/// settings store (ADR 0038 D3). Reuses the theme picker's persistence pattern
/// (`sharedPrefsProvider`-backed Notifier; ADR 0030): each setter mutates the
/// immutable state AND writes the matching key. Defensive parse: a missing or
/// out-of-range stored value falls back to the default instead of throwing
/// (ADR 0015 spirit). Tolerates a bare test container (no prefs override) by
/// falling back to in-memory-only so widget tests need not always seed prefs.
final appSettingsControllerProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings> {
  static const String _fontSizeKey = 'terminalFontSize';
  static const String _fontFamilyKey = 'terminalFontFamily';
  static const String _usernameKey = 'defaultUsername';
  static const String _portKey = 'defaultPort';
  static const String _keepAliveKey = 'keepAliveSeconds';
  static const String _confirmCloseKey = 'confirmOnCloseLiveSession';
  static const String _openOnLaunchKey = 'openOnLaunch';

  static const List<String> _allKeys = [
    _fontSizeKey,
    _fontFamilyKey,
    _usernameKey,
    _portKey,
    _keepAliveKey,
    _confirmCloseKey,
    _openOnLaunchKey,
  ];

  SharedPreferences? _prefs;

  @override
  AppSettings build() {
    try {
      _prefs = ref.read(sharedPrefsProvider);
    } catch (_) {
      _prefs = null; // bare container (some widget tests): in-memory only.
    }
    return _load();
  }

  AppSettings _load() {
    final p = _prefs;
    if (p == null) return AppSettings.defaults;

    final family = p.getString(_fontFamilyKey);
    final launch = p.getString(_openOnLaunchKey);
    return AppSettings(
      terminalFontSize: _clampFont(p.getInt(_fontSizeKey)),
      terminalFontFamily: kMonospaceFamilies.contains(family)
          ? family!
          : kDefaultFontFamily,
      defaultUsername: p.getString(_usernameKey) ?? '',
      defaultPort: _clampPort(p.getInt(_portKey)),
      keepAliveSeconds: _clampKeepAlive(p.getInt(_keepAliveKey)),
      confirmOnCloseLiveSession: p.getBool(_confirmCloseKey) ?? true,
      openOnLaunch:
          OpenOnLaunch.values.where((e) => e.name == launch).firstOrNull ??
          OpenOnLaunch.welcome,
    );
  }

  static int _clampFont(int? v) =>
      (v ?? kFontDefault.toInt()).clamp(kFontMin.toInt(), kFontMax.toInt());

  static int _clampPort(int? v) {
    if (v == null) return kDefaultPort;
    if (v < kPortMin || v > kPortMax) return kDefaultPort;
    return v;
  }

  static int _clampKeepAlive(int? v) => (v ?? 0).clamp(0, kKeepAliveMax);

  // --- Terminal (D5) ---

  void setTerminalFontSize(int size) {
    final v = _clampFont(size);
    state = state.copyWith(terminalFontSize: v);
    _prefs?.setInt(_fontSizeKey, v);
  }

  void setTerminalFontFamily(String family) {
    if (!kMonospaceFamilies.contains(family)) return;
    state = state.copyWith(terminalFontFamily: family);
    _prefs?.setString(_fontFamilyKey, family);
  }

  // --- Connection (D6) ---

  void setDefaultUsername(String username) {
    final v = username.trim();
    state = state.copyWith(defaultUsername: v);
    _prefs?.setString(_usernameKey, v);
  }

  void setDefaultPort(int port) {
    if (port < kPortMin || port > kPortMax) return;
    state = state.copyWith(defaultPort: port);
    _prefs?.setInt(_portKey, port);
  }

  void setKeepAliveSeconds(int seconds) {
    final v = seconds.clamp(0, kKeepAliveMax);
    state = state.copyWith(keepAliveSeconds: v);
    _prefs?.setInt(_keepAliveKey, v);
  }

  // --- Behavior (D7) ---

  void setConfirmOnCloseLiveSession(bool value) {
    state = state.copyWith(confirmOnCloseLiveSession: value);
    _prefs?.setBool(_confirmCloseKey, value);
  }

  void setOpenOnLaunch(OpenOnLaunch value) {
    state = state.copyWith(openOnLaunch: value);
    _prefs?.setString(_openOnLaunchKey, value.name);
  }

  // --- Danger zone (D10) ---

  /// Restore every setting to its default and clear the persisted keys. Only
  /// touches app preferences — the vault is untouched (the strongest reset
  /// stays with `reset_vault_dialog`).
  void reset() {
    state = AppSettings.defaults;
    final p = _prefs;
    if (p != null) {
      for (final k in _allKeys) {
        p.remove(k);
      }
    }
  }
}
