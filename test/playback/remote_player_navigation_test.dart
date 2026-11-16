import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/auth/store/credential_store.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/cast/cast_service.dart';
import 'package:moonfin/data/services/cast/cast_target.dart';
import 'package:moonfin/data/services/cast/native_airplay_channel.dart';
import 'package:moonfin/data/services/cast/native_cast_channel.dart';
import 'package:moonfin/data/services/cast/native_dlna_channel.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/theme_music_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/platform/pip_service.dart';
import 'package:moonfin/playback/playback_lifecycle_handler.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/playback/video_player_screen.dart';
import 'package:moonfin/ui/screensaver/screensaver_controller.dart';
import 'package:moonfin/ui/widgets/playback/next_up_overlay.dart';
import 'package:moonfin/ui/widgets/playback/tv_playback_failure.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/tv/tv_player_button.dart';
import 'package:moonfin/util/platform_detection.dart';

class _AuthStore extends Fake implements AuthenticationStore {}

class _AuthPrefs extends Fake implements AuthenticationPreferences {}

class _Credentials extends Fake implements CredentialStore {}

class _Socket extends Fake implements SocketHandler {}

class _Servers extends Fake implements ServerRepository {}

class _PluginSync extends Fake implements PluginSyncService {}

class _Manager extends PlaybackManager {
  int pauses = 0;
  int advances = 0;
  final seeks = <Duration>[];
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);
  @override
  Future<void> nextInQueue() async => advances++;
  @override
  Future<void> stop({bool userInitiated = true}) async {}
}

class _RecoveryManager extends _Manager {
  final _changes = StreamController<PlaybackBringupState>.broadcast(sync: true);
  var _bringup = const PlaybackBringupState(
    phase: PlaybackBringupPhase.failed,
    error: 'Playback failed.',
  );
  int retries = 0;
  @override
  PlaybackBringupState get bringupState => _bringup;
  @override
  Stream<PlaybackBringupState> get bringupStateStream => _changes.stream;
  @override
  Future<void> changeBitrate(int? mbps) async {
    retries++;
    _bringup = const PlaybackBringupState(phase: PlaybackBringupPhase.ready);
    _changes.add(_bringup);
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}

class _Client extends Fake implements MediaServerClient {
  @override
  ServerType get serverType => ServerType.emby;
  @override
  TrickplayApi? get trickplayApi => null;
}

class _Factory extends Fake implements MediaServerClientFactory {
  @override
  MediaServerClient? getClientIfExists(String id) => null;
}

class _Cast extends Fake implements CastService {
  @override
  final activeKindNotifier = ValueNotifier<CastTargetKind?>(null);
  @override
  final remoteStateNotifier = ValueNotifier<String?>(null);
  @override
  final remotePositionNotifier = ValueNotifier<int>(0);
  @override
  CastTargetKind? get activeKind => null;
}

class _ThemeMusic extends Fake implements ThemeMusicService {
  @override
  void setExternalAudioActive(bool active) {}
}

class _Screensaver extends Fake implements ScreensaverController {
  @override
  void setPlaybackActive(bool active) {}
}

class _Lifecycle extends Fake implements PlaybackLifecycleHandler {}

void main() {
  late _Manager manager;
  late PipService pip;
  late SessionRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    manager = _Manager();
    manager.state.setPlaying(true);
    manager.state.setDuration(const Duration(minutes: 30));
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    GetIt.instance.registerSingleton<UserRepository>(UserRepository());
    GetIt.instance.registerSingleton<MediaServerClient>(_Client());
    GetIt.instance.registerSingleton<MediaServerClientFactory>(_Factory());
    GetIt.instance.registerSingleton<CastService>(_Cast());
    GetIt.instance.registerSingleton<NativeCastChannel>(NativeCastChannel());
    GetIt.instance.registerSingleton<NativeDlnaChannel>(NativeDlnaChannel());
    GetIt.instance.registerSingleton<NativeAirPlayChannel>(
      NativeAirPlayChannel(),
    );
    pip = PipService();
    GetIt.instance.registerSingleton<PipService>(pip);
    GetIt.instance.registerSingleton<PlaybackLifecycleHandler>(_Lifecycle());
    GetIt.instance.registerSingleton<ThemeMusicService>(_ThemeMusic());
    GetIt.instance.registerSingleton<ScreensaverController>(_Screensaver());
    repository = SessionRepository(
      _AuthStore(),
      _AuthPrefs(),
      _Credentials(),
      _Factory(),
      _Socket(),
      _Servers(),
      GetIt.instance<UserRepository>(),
      _PluginSync(),
    );
  });

  tearDown(() async {
    repository.dispose();
    manager.dispose();
    pip.dispose();
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const VideoPlayerScreen(),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String command) async {
    await repository.handleRemoteCommandForTest(
      GeneralCommandMessage(name: command),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'TV failed player offers Retry and returns focus to transport after recovery',
    (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      addTearDown(
        () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
      );
      await GetIt.instance.unregister<PlaybackManager>();
      manager.dispose();
      final recovery = _RecoveryManager();
      manager = recovery;
      GetIt.instance.registerSingleton<PlaybackManager>(manager);
      await open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TvPlaybackFailure), findsOneWidget);
      expect(
        find.byTooltip('Playback speed'),
        findsNothing,
        reason:
            'Hidden transport controls do not remain reachable under failure',
      );
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Tv26Button>()
            ?.label,
        'Retry',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(recovery.retries, 1);
      expect(find.byType(TvPlaybackFailure), findsNothing);
      final primary = FocusManager.instance.primaryFocus;
      expect(
        tester
            .widgetList<TvPlayerButton>(find.byType(TvPlayerButton))
            .where((button) => button.focusNode == primary),
        hasLength(1),
        reason: 'Recovery must land on a mounted TV transport control',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> showNextUp(WidgetTester tester, {bool playing = true}) async {
    manager.state.setPlaying(playing);
    manager.queueService.setQueue([
      const AggregatedItem(
        id: 'one',
        serverId: 'server',
        rawData: {'Type': 'Episode', 'Name': 'One'},
      ),
      const AggregatedItem(
        id: 'two',
        serverId: 'server',
        rawData: {'Type': 'Episode', 'Name': 'Two'},
      ),
    ]);
    await tester.pump();
    manager.state.setPosition(
      const Duration(minutes: 29, seconds: 59, milliseconds: 800),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'normal player remote reveals mounted controls and Select runs once',
    (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 10));
      await tap(tester, 'MoveDown');
      final primary = FocusManager.instance.primaryFocus;
      expect(primary?.context, isNotNull);
      expect(
        tester
            .widgetList<IconButton>(find.byType(IconButton))
            .where((button) => button.focusNode == primary),
        hasLength(1),
      );
      for (var i = 0; i < 2; i++) {
        await tap(tester, 'MoveRight');
        expect(FocusManager.instance.primaryFocus, isNot(primary));
        await tap(tester, 'MoveLeft');
        expect(FocusManager.instance.primaryFocus, primary);
      }
      expect(
        manager.seeks,
        isEmpty,
        reason: 'remote arrows navigate rather than seek',
      );
      await tap(tester, 'Select');
      expect(manager.pauses, 1);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'paused seeking near the end cannot start an auto-next countdown',
    (tester) async {
      await open(tester);
      await showNextUp(tester, playing: false);
      expect(find.byType(NextUpOverlay), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(manager.advances, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Next Up owns remote focus ahead of normal playback controls',
    (tester) async {
      await open(tester);
      await tap(tester, 'MoveDown');
      await showNextUp(tester);
      expect(find.byType(NextUpOverlay), findsOneWidget);
      final nextUp = tester.widget<NextUpOverlay>(find.byType(NextUpOverlay));
      expect(nextUp.focusNode?.hasFocus, isTrue);
      await tap(tester, 'MoveRight');
      await tester.pump(const Duration(milliseconds: 100));
      expect(nextUp.dismissFocusNode?.hasFocus, isTrue);
      await tap(tester, 'MoveLeft');
      expect(nextUp.focusNode?.hasFocus, isTrue);
      await tap(tester, 'Select');
      expect(manager.advances, 1);
      expect(manager.pauses, 0);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'Next Up close button dismisses the card and keeps the episode playing',
    (tester) async {
      await open(tester);
      await showNextUp(tester);
      expect(find.byType(NextUpOverlay), findsOneWidget);
      expect(manager.suppressAutoNext, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(NextUpOverlay),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      // On touch layouts the tap only lands once the double tap window ends.
      await tester.pump(kDoubleTapTimeout);
      await tester.pump();

      expect(find.byType(NextUpOverlay), findsNothing);
      expect(
        manager.suppressAutoNext,
        isFalse,
        reason: 'the episode ends on its own once the card is dismissed',
      );
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
}
