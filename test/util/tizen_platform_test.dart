import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Tizen is leanback without desktop, downloads or ambient decoders',
    () async {
      // Run with --dart-define=MOONFIN_TIZEN=true.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      addTearDown(
        () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
      );
      expect(PlatformDetection.isTV, isTrue);
      expect(PlatformDetection.useLeanbackUi, isTrue);
      expect(PlatformDetection.isLinux, isFalse);
      expect(PlatformDetection.isDesktop, isFalse);
      expect(PlatformDetection.supportsOfflineDownloads, isFalse);
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(UserPreferences.mediaBarTrailerPreview, true);
      await prefs.set(UserPreferences.episodePreviewEnabled, true);
      expect(prefs.resolveMediaBarTrailerPreview(), isFalse);
      expect(prefs.resolveMediaPreviewMode(), UserPreferences.mediaPreviewOff);
    },
    skip: !PlatformDetection.isTizen,
  );
}
