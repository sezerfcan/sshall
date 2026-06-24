import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

/// Overridden in main() after SharedPreferences is loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'));

final themeControllerProvider =
    NotifierProvider<ThemeController, AppThemeId>(ThemeController.new);

class ThemeController extends Notifier<AppThemeId> {
  static const _key = 'themeId';

  @override
  AppThemeId build() {
    final prefs = ref.read(sharedPrefsProvider);
    final saved = prefs.getString(_key);
    return AppThemeId.values
        .firstWhere((e) => e.name == saved, orElse: () => AppThemeId.night);
  }

  void set(AppThemeId id) {
    state = id;
    ref.read(sharedPrefsProvider).setString(_key, id.name);
  }
}
