import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/theme/app_theme.dart' as theming;
import 'package:moonfin/ui/theme/app_theme_controller.dart';
import 'package:moonfin/ui/theme/vibrance.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _black = Color(0xFF000000);

Future<UserPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'pref_last_server_id': 'srv1',
    'pref_last_user_id': 'usr1',
  });
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ThemeRegistry.setOledTuning(OledTuning.off);
    Vibrance.apply(OledTuning.off);
  });

  test('defaults to off, leaving the chosen theme untouched', () async {
    final prefs = await _prefs();
    final controller = AppThemeController.fromPreferences(prefs);
    final authored = ThemeRegistry.resolveById(controller.activeSpec.id);

    expect(controller.activeSpec.colors.background, authored.colors.background);
    expect(Vibrance.filter.value, isNull);
  });

  test(
    'saved appearance cannot override the fixed product theme at startup',
    () async {
      final prefs = await _prefs();
      await prefs.set(UserPreferences.visualTheme, VisualThemeId.neonPulse);
      await prefs.set(UserPreferences.oledMode, OledMode.vivid);
      final controller = AppThemeController.fromPreferences(prefs);
      expect(controller.activeThemeId, VisualThemeId.moonfin);
      expect(controller.activeSpec.colors.background, _black);
      expect(Vibrance.filter.value, isNull);
      expect(prefs.get(UserPreferences.visualTheme), VisualThemeId.neonPulse);
      expect(prefs.get(UserPreferences.oledMode), OledMode.vivid);
    },
  );

  test(
    'preference refresh preserves the shared palette and typography',
    () async {
      final prefs = await _prefs();
      final controller = AppThemeController.fromPreferences(prefs);
      final authored = controller.activeSpec;
      await prefs.set(UserPreferences.visualTheme, VisualThemeId.neonPulse);
      await prefs.set(UserPreferences.oledMode, OledMode.vivid);
      controller.refreshFromPreferences(prefs);
      expect(controller.activeSpec.colors, authored.colors);
      expect(AppColorScheme.surface, Tv26Style.surface);
      expect(Vibrance.filter.value, isNull);
      final theme = theming.AppTheme.buildTheme(controller.activeSpec);
      expect(theme.scaffoldBackgroundColor, Tv26Style.canvas);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    },
  );
}
