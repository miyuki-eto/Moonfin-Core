import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screensaver/screensaver_controller.dart';
import 'package:moonfin/ui/screensaver/screensaver_host.dart';
import 'package:moonfin/ui/screensaver/screensaver_view.dart';
import 'package:moonfin/ui/tv/tv_reveal_transition.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Playback extends Mock implements PlaybackManager {}

void main() {
  testWidgets(
    'TV idle entry reveals a clock and consumes the complete dismissal key hold',
    (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(
        UserPreferences.screensaverTimeout,
        ScreensaverTimeout.m1,
      );
      final state = PlayerState();
      final playback = _Playback();
      when(() => playback.state).thenReturn(state);
      GetIt.instance.registerSingleton<UserPreferences>(prefs);
      final controller = ScreensaverController(prefs, playback);
      GetIt.instance.registerSingleton<ScreensaverController>(controller);
      addTearDown(() async {
        state.dispose();
        await GetIt.instance.reset();
        PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ScreensaverHost())),
      );
      expect(controller.visible.value, isFalse);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 3));
      expect(controller.visible.value, isTrue);
      expect(find.byType(ScreensaverClock), findsOneWidget);
      expect(find.byType(TvRevealTransition), findsWidgets);
      expect(find.byType(Image), findsNothing);
      expect(
        controller.handleKeyEvent(
          const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
          ),
        ),
        isTrue,
      );
      expect(controller.visible.value, isFalse);
      expect(
        controller.handleKeyEvent(
          const KeyRepeatEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
          ),
        ),
        isTrue,
      );
      expect(
        controller.handleKeyEvent(
          const KeyUpEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
          ),
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ScreensaverView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
