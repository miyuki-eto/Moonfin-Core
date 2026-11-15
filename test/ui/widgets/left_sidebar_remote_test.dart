import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/left_sidebar.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Views extends ChangeNotifier implements UserViewsRepository {
  @override
  Future<List<AggregatedLibrary>> getUserViews() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plugin extends ChangeNotifier implements PluginSyncService {
  @override
  bool get seerrAvailable => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seerr extends Fake implements SeerrPreferences {
  @override
  String labelOrDefault(String fallback) => fallback;
}

class _Games extends Fake implements GameLibraryRegistry {
  @override
  Future<void> refresh() async {}
}

class _Factory extends Fake implements MediaServerClientFactory {}

void main() {
  setUp(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    await prefs.set(UserPreferences.enableMultiServerLibraries, false);
    await prefs.set(UserPreferences.showShuffleButton, false);
    await prefs.set(UserPreferences.showGenresButton, true);
    await prefs.set(UserPreferences.showServerMessagesButton, false);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    GetIt.instance.registerSingleton<UserRepository>(UserRepository());
    GetIt.instance.registerSingleton<UserViewsRepository>(_Views());
    GetIt.instance.registerSingleton<PluginSyncService>(_Plugin());
    GetIt.instance.registerSingleton<SeerrPreferences>(_Seerr());
    GetIt.instance.registerSingleton<GameLibraryRegistry>(_Games());
    GetIt.instance.registerSingleton<PlaybackManager>(PlaybackManager());
    GetIt.instance.registerSingleton<MediaServerClientFactory>(_Factory());
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    GetIt.instance<PlaybackManager>().dispose();
    await GetIt.instance.reset();
  });

  testWidgets(
    'Left opens the real TV sidebar; arrows and Enter select a route',
    (tester) async {
      final content = FocusNode(debugLabel: 'catalogue');
      addTearDown(content.dispose);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              body: Stack(
                children: [
                  Center(
                    child: Focus(
                      focusNode: content,
                      autofocus: true,
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          NavigationLayout.focusNavbarNotifier.value!();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: const Text('Catalogue'),
                    ),
                  ),
                  LeftSidebar(activeRoute: '/home', contentFocusNode: content),
                ],
              ),
            ),
          ),
          GoRoute(
            path: Destinations.allGenres,
            builder: (_, _) => const Text('Genre catalogue'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
        ),
      );
      await tester.pumpAndSettle();
      expect(content.hasFocus, isTrue);
      Future<void> key(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      String? focusedLabel() {
        final context = FocusManager.instance.primaryFocus?.context;
        return context?.findAncestorWidgetOfExactType<Tv26Button>()?.label;
      }

      await key(LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), 'Home');
      expect(find.byKey(const ValueKey('sidebar-settings')), findsNothing);
      expect(find.text('Settings'), findsNothing);
      await key(LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'Search');
      await key(LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'Home');
      await key(LogicalKeyboardKey.arrowRight);
      expect(content.hasFocus, isTrue);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), 'Home');
      await key(LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'Genres');
      expect(
        tester
            .widget<Image>(
              find.descendant(
                of: find.byKey(const ValueKey('sidebar-genres')),
                matching: find.byType(Image),
              ),
            )
            .color,
        Colors.black,
        reason:
            'Custom sidebar artwork must contrast with the focused white row',
      );
      await key(LogicalKeyboardKey.enter);
      expect(find.text('Genre catalogue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
