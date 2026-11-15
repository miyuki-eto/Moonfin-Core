import 'dart:io';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/services/recent_searches_store.dart';
import 'package:moonfin/ui/screens/search/search_screen.dart';
import 'package:moonfin/ui/screens/browse/all_genres_screen.dart';
import 'package:moonfin/ui/screens/browse/favorites_screen.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/ui/screens/settings/settings_side_panel.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/background_service.dart';
import 'package:moonfin/data/services/connectivity_service.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/services/theme_music_service.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart' hide AppTheme;
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/app_router.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';
import 'package:moonfin/ui/screens/detail/nouveau/discovery/nouveau_discovery_rail.dart';
import 'package:moonfin/ui/screens/detail/nouveau/extras/nouveau_extras_section.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';
import 'package:moonfin/ui/screens/browse/folder_browse_screen.dart';
import 'package:moonfin/ui/tv/tv_modal.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/mediabar/tv_featured_hero.dart';
import 'package:moonfin/ui/tv/tv_remote_navigation.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/util/focus/gamepad/gamepad_navigation_scope.dart';
import 'package:moonfin/util/focus/input_mode_tracker.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin/util/tv_ui_scale.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/artwork_fixture.dart';

// The production router, screens, focus scopes, detail/library view models and
// Jellyfin API parser run here. Only Home's feed, HTTP responses, connectivity,
// and theme audio are controlled. Video decoding and native remotes need device
// checks. Unexpected HTTP endpoints fail rather than returning generic success.
class _Session extends Mock implements SessionRepository {}

class _ThemeMusic extends Mock implements ThemeMusicService {}

class _Online extends ChangeNotifier implements ConnectivityService {
  @override
  bool get canReachServer => true;
  @override
  bool get isOnline => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Offline extends Fake implements OfflineRepository {
  @override
  Future<DownloadedItem?> getItem(String id) async => null;
  @override
  Future<List<DownloadedItem>> getSeriesEpisodes(String id) async => [];
  @override
  Future<List<DownloadedItem>> getSeasonEpisodes(String id) async => [];
}

class _HeroFeed extends ChangeNotifier implements MediaBarViewModel {
  @override
  List<MediaBarSlideItem> get items => const [
    MediaBarSlideItem(
      itemId: 'movie-0',
      serverId: 'http://tv.test',
      title: 'Film 0',
    ),
    MediaBarSlideItem(
      itemId: 'movie-1',
      serverId: 'http://tv.test',
      title: 'Film 1',
    ),
  ];
  @override
  MediaBarState get state => MediaBarReady(items);
  @override
  Future<void> ensureRatings(String itemId) async {}
  @override
  Map<String, double> ratingsFor(String itemId) => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HomeFeed extends ChangeNotifier implements HomeViewModel {
  @override
  ImageApi imageApiForServer(String serverId) =>
      GetIt.instance<MediaServerClient>().imageApi;
  @override
  final MediaBarViewModel mediaBarViewModel = _HeroFeed();
  @override
  List<HomeRow> get rows => [
    for (var row = 0; row < 3; row++)
      HomeRow(
        id: 'row-$row',
        title: 'Row $row',
        rowType: HomeRowType.latestMedia,
        items: [
          for (var i = 0; i < 8; i++)
            AggregatedItem(
              id: 'movie-$i',
              serverId: 'http://tv.test',
              rawData: movie(i),
            ),
        ],
      ),
  ];
  @override
  bool get isLoading => false;
  @override
  bool get hasDeferredSections => false;
  @override
  Future<void> load({
    bool preserveExisting = false,
    bool forceRefresh = false,
    bool newSectionsOnly = false,
  }) async {}
  @override
  Future<void> refresh({
    bool preserveExisting = true,
    bool newMediaBar = false,
    bool newSectionsOnly = false,
  }) async {}
  @override
  Future<void> refreshResumeAndNextUp() async {}
  @override
  void applyUserDataChanges() {}
  @override
  Future<void> loadMoreForRow(int index) async {}
  @override
  void dispose() {
    mediaBarViewModel.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> movie(int i) => {
  'Id': 'movie-$i',
  'Type': 'Movie',
  'Name': 'Film $i',
  'Overview': 'A synopsis for Film $i.',
  'RunTimeTicks': 60000000000,
  'Genres': ['Drama'],
  'People': [
    {'Id': 'director', 'Name': 'A Director', 'Type': 'Director'},
    {'Id': 'actor', 'Name': 'An Actor', 'Type': 'Actor'},
  ],
  'MediaSources': [
    {
      'Id': 'source',
      'MediaStreams': [
        {'Type': 'Video', 'Index': 0, 'Codec': 'h264'},
        {'Type': 'Audio', 'Index': 1, 'Codec': 'aac', 'Language': 'eng'},
        {'Type': 'Subtitle', 'Index': 2, 'Codec': 'srt', 'Language': 'eng'},
      ],
    },
    if (i == 7)
      {
        'Id': 'alternate',
        'Name': 'Alternate Cut',
        'Container': 'mkv',
        'Bitrate': 8000000,
        'MediaStreams': [
          {'Type': 'Video', 'Index': 0, 'Codec': 'h264'},
        ],
      },
  ],
  'UserData': {'PlaybackPositionTicks': i == 1 ? 600000000 : 0},
};

void main() {
  testWidgets(
    'production TV journey: Home, movie, Back, sidebar, library and return',
    (tester) async {
      await GetIt.instance.reset();
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(UserPreferences.navbarPosition, NavbarPosition.left);
      await prefs.set(UserPreferences.mediaBarAutoAdvance, false);
      await prefs.set(UserPreferences.showShuffleButton, false);
      await prefs.set(UserPreferences.showGenresButton, true);
      await prefs.set(UserPreferences.showFavoritesButton, true);
      await prefs.set(UserPreferences.showLibrariesInToolbar, true);
      await prefs.set(UserPreferences.showLibrariesIndividually, false);
      await prefs.set(UserPreferences.showServerMessagesButton, false);
      await prefs.set(UserPreferences.enableMultiServerLibraries, false);
      await prefs.set(
        UserPreferences.recommendationSystemSource,
        RecommendationSystemSource.server,
      );
      final unexpected = <String>[];
      final requests = <RequestOptions>[];
      final favorites = <String>{};
      userDataSync.reset();
      Completer<void>? detailResponse;
      Completer<void>? favoriteResponse;
      var libraryOffline = false;
      final libraries = [
        {
          'Id': 'movies',
          'Name': 'Movies',
          'Type': 'CollectionFolder',
          'CollectionType': 'movies',
        },
        {
          'Id': 'shows',
          'Name': 'TV Shows',
          'Type': 'CollectionFolder',
          'CollectionType': 'tvshows',
        },
      ];
      Object? response(RequestOptions request) {
        requests.add(request);
        final path = request.uri.path;
        if (path.startsWith('/UserFavoriteItems/') &&
            (request.method == 'POST' || request.method == 'DELETE')) {
          final id = path.split('/').last;
          if (request.method == 'POST') {
            favorites.add(id);
          } else {
            favorites.remove(id);
          }
          return <String, dynamic>{};
        }
        if (request.method == 'POST' && path.endsWith('/PlaybackInfo')) {
          return {'MediaSources': movie(0)['MediaSources']};
        }
        if (request.method != 'GET') {
          unexpected.add('${request.method} $path');
          return null;
        }
        if (path == '/UserViews') {
          return {'Items': libraries};
        }
        if (path == '/Users/Me' ||
            path == '/Users/viewer' ||
            path == '/Users/viewer/Configuration') {
          return {'Configuration': {}, 'Policy': {}};
        }
        if (path == '/Users/viewer/Items/movies') {
          return libraries.first;
        }
        if (path == '/Users/viewer/Items/shows') {
          return libraries.last;
        }
        if (path == '/Users/viewer/Items/collection') {
          return {
            'Id': 'collection',
            'Name': 'Film Collection',
            'Type': 'BoxSet',
          };
        }
        if (path == '/Users/viewer/Items/folder') {
          return {
            'Id': 'folder',
            'Name': 'Cinema',
            'Type': 'Folder',
            'ParentId': 'movies',
          };
        }
        if (RegExp(r'^/Users/viewer/Items/movie-\d+$').hasMatch(path)) {
          final id = path.split('/').last;
          final item = movie(int.parse(id.split('-').last));
          return {
            ...item,
            'UserData': {
              ...item['UserData'] as Map,
              'IsFavorite': favorites.contains(id),
            },
          };
        }
        if (path == '/Users/viewer/Items/director' ||
            path == '/Users/viewer/Items/actor') {
          return {
            'Id': path.split('/').last,
            'Name': 'A Person',
            'Type': 'Person',
          };
        }
        if (path.endsWith('/Similar')) {
          return {
            'Items': [movie(2), movie(3)],
            'TotalRecordCount': 2,
          };
        }
        if ((path == '/Users/viewer/Items' || path == '/Items') &&
            request.queryParameters['IncludeItemTypes'] == 'BoxSet') {
          return {'Items': [], 'TotalRecordCount': 0};
        }
        if (path == '/Users/viewer/Items' || path == '/Items') {
          if (request.queryParameters['ParentId'] == 'collection' ||
              request.queryParameters['ParentId'] == 'folder') {
            return {
              'Items': [movie(4), movie(5)],
              'TotalRecordCount': 2,
            };
          }
          if (request.queryParameters['IsFavorite'] == true) {
            final types = request.queryParameters['IncludeItemTypes'];
            final items =
                types == null || types.toString().split(',').contains('Movie')
                ? [
                    for (final id in favorites)
                      {
                        ...movie(int.parse(id.split('-').last)),
                        'UserData': {'IsFavorite': true},
                      },
                  ]
                : <Map<String, dynamic>>[];
            return {'Items': items, 'TotalRecordCount': items.length};
          }
          return {
            'Items': [for (var i = 0; i < 8; i++) movie(i)],
            'TotalRecordCount': 8,
          };
        }
        if (path == '/DisplayPreferences/drama' ||
            path == '/DisplayPreferences/movies' ||
            path == '/DisplayPreferences/shows') {
          return {'Id': path.split('/').last, 'CustomPrefs': {}};
        }
        if (path == '/Items/Filters') {
          return {
            'Genres': ['Drama'],
            'Tags': [],
            'Years': [],
          };
        }
        if (path == '/Items/Filters2') {
          return {
            'Genres': [
              {'Name': 'Drama', 'Id': 'drama'},
            ],
            'Tags': [],
            'Years': [],
          };
        }
        if (path == '/Genres') {
          return {
            'Items': [
              {'Id': 'drama', 'Name': 'Drama', 'Type': 'Genre'},
            ],
            'TotalRecordCount': 1,
          };
        }
        if (path == '/Users/viewer/Items/movie-7/SpecialFeatures' ||
            path == '/Items/movie-7/SpecialFeatures') {
          return [
            {
              ...movie(8),
              'Name': 'Behind the Scenes',
              'ExtraType': 'BehindTheScenes',
            },
          ];
        }
        if (path.endsWith('/SpecialFeatures') ||
            path.endsWith('/AdditionalParts') ||
            path.endsWith('/LocalTrailers') ||
            path.endsWith('/Ancestors')) {
          return [];
        }
        unexpected.add('${request.method} $path');
        return null;
      }

      final client = JellyfinMediaServerClient(
        baseUrl: 'http://tv.test',
        deviceInfo: const DeviceInfo(
          id: 'test',
          name: 'TV flow test',
          appName: 'Moonfin',
          appVersion: 'test',
        ),
        interceptors: [
          InterceptorsWrapper(
            onRequest: (request, handler) async {
              if (libraryOffline) {
                handler.reject(
                  DioException(
                    requestOptions: request,
                    type: DioExceptionType.connectionError,
                    error: 'Controlled library outage',
                  ),
                );
                return;
              }
              if (request.method == 'DELETE' &&
                  request.uri.path.startsWith('/UserFavoriteItems/')) {
                await favoriteResponse?.future;
              }
              if (RegExp(r'^/Users/viewer/Items/movie-\d+$')
                  .hasMatch(request.uri.path)) {
                await detailResponse?.future;
              }
              final data = response(request);
              if (data == null) {
                handler.reject(
                  DioException(
                    requestOptions: request,
                    error:
                        'No fixture for ${request.method} ${request.uri.path}',
                  ),
                );
                return;
              }
              handler.resolve(
                Response(requestOptions: request, statusCode: 200, data: data),
              );
            },
          ),
        ],
      )..userId = 'viewer';
      final session = _Session();
      when(() => session.activeUserId).thenReturn('viewer');
      final themeMusic = _ThemeMusic();
      registerFallbackValue(
        AggregatedItem(
          id: 'fallback',
          serverId: 'http://tv.test',
          rawData: movie(0),
        ),
      );
      when(() => themeMusic.fadeOutAndStop()).thenAnswer((_) async {});
      when(() => themeMusic.playForItem(any())).thenAnswer((_) async {});
      final tmdb = TmdbRepository(client);
      final background = BackgroundService();
      final playback = PlaybackManager();
      final home = _HomeFeed();
      GetIt.instance.registerSingleton<UserPreferences>(prefs);
      GetIt.instance.registerSingleton<SessionRepository>(session);
      GetIt.instance.registerSingleton<UserRepository>(UserRepository());
      GetIt.instance.registerSingleton<ConnectivityService>(_Online());
      GetIt.instance.registerSingleton<ThemeMusicService>(themeMusic);
      GetIt.instance.registerSingleton<BackgroundService>(background);
      GetIt.instance.registerSingleton<MediaServerClient>(client);
      GetIt.instance.registerSingleton<MediaServerClientFactory>(
        MediaServerClientFactory(deviceInfo: client.deviceInfo),
      );
      GetIt.instance.registerSingleton<PlaybackManager>(playback);
      GetIt.instance.registerSingleton<HomeViewModel>(home);
      GetIt.instance.registerSingleton<PluginSyncService>(
        PluginSyncService(prefs, store),
      );
      GetIt.instance.registerSingleton<SeerrPreferences>(
        SeerrPreferences(store, session),
      );
      GetIt.instance.registerSingleton<TmdbRepository>(tmdb);
      GetIt.instance.registerSingleton<MdbListRepository>(
        MdbListRepository(client, tmdb),
      );
      GetIt.instance.registerSingleton<RowDataSource>(RowDataSource(client));
      GetIt.instance.registerSingleton<UserViewsRepository>(
        UserViewsRepository(client),
      );
      GetIt.instance.registerSingleton<SearchRepository>(
        SearchRepository(client),
      );
      GetIt.instance.registerSingleton<RecentSearchesStore>(
        RecentSearchesStore(store),
      );
      GetIt.instance.registerSingleton<OfflineRepository>(_Offline());
      GetIt.instance.registerSingleton<GameLibraryRegistry>(
        GameLibraryRegistry()..seed([]),
      );
      final artwork = (await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp('moonfin-flow-art');
        final png = await writeTestPng(temp, width: 400, height: 225);
        return (temp: temp, png: png);
      }))!;
      final previousCacheManager =
          CachedNetworkImageProvider.defaultCacheManager;
      CachedNetworkImageProvider.defaultCacheManager = FakeArtworkCacheManager(
        artwork.png,
      );
      appRouter.go('/home');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            shortcuts: {
              ...WidgetsApp.defaultShortcuts,
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  const ScrollIntent(direction: AxisDirection.up),
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const ScrollIntent(direction: AxisDirection.down),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  const ScrollIntent(direction: AxisDirection.left),
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  const ScrollIntent(direction: AxisDirection.right),
            },
            theme: AppTheme.buildTheme(ThemeRegistry.active),
            routerConfig: appRouter,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            builder: (_, child) => TvRemoteNavigation(
              child: InputModeTracker(
                child: Focus(
                  debugLabel: 'GlobalShortcutScope',
                  skipTraversal: true,
                  includeSemantics: false,
                  child: GamepadNavigationScope(
                    child: TvUiScale(child: child!),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        background.dispose();
        playback.dispose();
        home.dispose();
        userDataSync.reset();
        await GetIt.instance.reset();
        CachedNetworkImageProvider.defaultCacheManager = previousCacheManager;
        PaintingBinding.instance.imageCache.clear();
        await tester.runAsync(() => artwork.temp.delete(recursive: true));
        PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
        tester.view.reset();
      });
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          unexpected,
          isEmpty,
          reason: 'unexpected API calls must fail at the step that made them',
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> key(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await settle();
      }

      String? label() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<Tv26Button>()
          ?.label;
      await settle();
      expect(
        label(),
        'Play',
        reason: 'Home starts on a real action without Tab or a click',
      );
      expect(
        ReadingOrderTraversalPolicy()
            .findFirstFocus(
              FocusScope.of(tester.element(find.byType(TvFeaturedHero))),
              ignoreCurrentFocus: true,
            )
            ?.debugLabel,
        'featuredPlay',
        reason: 'Collapsed navigation is not an automatic landing target',
      );
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowRight);
      final homeCard = FocusManager.instance.primaryFocus;
      final homeRow = homeCard?.context
          ?.findAncestorStateOfType<LockedFocusRowState<AggregatedItem>>();
      expect(homeRow?.focusedIndex, 1);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(label(), 'Resume');
      final routeScope = FocusScope.of(
        tester.element(find.byType(ItemDetailScreen)),
      );
      expect(
        ReadingOrderTraversalPolicy()
            .findFirstFocus(routeScope, ignoreCurrentFocus: true)
            ?.debugLabel,
        'detailInitialContent',
        reason: 'Automatic browser view focus must start in content, not Back',
      );
      final actions = tester
          .widgetList<Tv26Button>(
            find.descendant(
              of: find.byType(DetailActionButtons),
              matching: find.byType(Tv26Button),
            ),
          )
          .where((button) => button.label != 'Back')
          .map((button) => button.label)
          .toList();
      expect(actions.first, 'Resume');
      expect(actions.last, 'More');
      for (var index = 0; index < actions.length; index++) {
        for (var right = 0; right < index; right++) {
          await key(LogicalKeyboardKey.arrowRight);
        }
        expect(
          label(),
          actions[index],
          reason: 'Every visible action is reachable',
        );
        await key(LogicalKeyboardKey.arrowUp);
        expect(
          label(),
          'Read More',
          reason: 'Up from ${actions[index]} reaches the synopsis control',
        );
        await key(LogicalKeyboardKey.enter);
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('A synopsis for Film 1.'),
          ),
          findsOneWidget,
        );
        await key(LogicalKeyboardKey.escape);
        expect(label(), 'Read More');
        await key(LogicalKeyboardKey.arrowDown);
        expect(
          label(),
          actions[index],
          reason: 'Down restores the last action',
        );
        await key(LogicalKeyboardKey.arrowUp);
        await key(LogicalKeyboardKey.arrowUp);
        expect(
          label(),
          'Back',
          reason: 'A second Up from ${actions[index]} reaches Back',
        );
        await key(LogicalKeyboardKey.arrowDown);
        expect(label(), 'Resume');
      }
      for (var right = 1; right < actions.length; right++) {
        await key(LogicalKeyboardKey.arrowRight);
      }
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(Dialog), findsOneWidget);
      await key(LogicalKeyboardKey.escape);
      expect(label(), 'More', reason: 'Cancelling More restores its trigger');
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'A Director');
      FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      await key(LogicalKeyboardKey.arrowUp);
      expect(
        label(),
        'Back',
        reason:
            'Credits retain their ancestor Back handler after view focus loss',
      );
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Resume');
      await key(LogicalKeyboardKey.arrowDown);
      final similarFocus = FocusManager.instance.primaryFocus;
      expect(similarFocus?.debugLabel, contains('discovery'));
      final similarRail = find.descendant(
        of: find.byType(NouveauDiscoveryRail).first,
        matching: find.byType(LockedFocusRow<AggregatedItem>),
      );
      expect(
        tester
            .widget<LockedFocusRow<AggregatedItem>>(similarRail)
            .viewportInsets,
        Tv26Style.railPadding,
      );
      expect(homeRow!.widget.padding.left, Tv26Style.railPadding.left);
      expect(homeRow.widget.padding.right, Tv26Style.railPadding.right);
      expect(
        tester
            .getSize(
              find.descendant(
                of: similarRail,
                matching: find.byType(ShaderMask),
              ),
            )
            .width,
        closeTo(
          (homeRow.context.findRenderObject()! as RenderBox).size.width +
              2 * (Tv26Style.focusOutset + Tv26Style.railFadeDistance),
          .01,
        ),
        reason: 'Home and Similar use the same full-width fade viewport',
      );
      await key(LogicalKeyboardKey.arrowRight);
      final similarCard = FocusManager.instance.primaryFocus;
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(label(), 'Play');
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Read More');
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Back');
      await key(LogicalKeyboardKey.enter);
      expect(
        FocusManager.instance.primaryFocus,
        same(similarCard),
        reason: 'Nested detail returns to its Similar card',
      );
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Resume');
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Read More');
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Back', reason: 'Back remains reachable above Read More');
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), startsWith('Resume'));
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(homeCard));
      expect(
        homeRow.focusedIndex,
        1,
        reason: 'Back preserves the selected Home card',
      );
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(
        label(),
        'Home',
        reason: 'Left at the first card enters the sidebar',
      );
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Search');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Retro TV');
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Genres');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Libraries');
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Movies');
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(LibraryBrowseScreen), findsOneWidget);
      expect(
        label(),
        'Recently Added',
        reason: 'Library starts on its selected category',
      );
      await key(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'grid_item:0');
      await key(LogicalKeyboardKey.arrowRight);
      detailResponse = Completer<void>();
      await key(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      detailResponse.complete();
      await settle();
      expect(
        label(),
        'Resume',
        reason: 'Slow detail loads claim their visible action after the initial retry window',
      );
      detailResponse = null;
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Read More');
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Back');
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'grid_item:1',
        reason: 'Back restores the same library card',
      );
      await key(LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'grid_item:7');
      await key(LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'grid_item:7',
        reason: 'Down on the final grid row cannot fall into the taller panel',
      );
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Recently Added');
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Movies');
      await key(LogicalKeyboardKey.enter);
      expect(
        label(),
        'Movies',
        reason: 'Selecting Movies keeps focus on Movies',
      );
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Recently Added');
      await key(LogicalKeyboardKey.enter);
      expect(
        label(),
        'Recently Added',
        reason: 'Changing category retains focus',
      );
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Recently Added');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), '4K');
      await key(LogicalKeyboardKey.enter);
      expect(label(), '4K');
      expect(
        requests
            .where(
              (r) =>
                  r.uri.path == '/Items' || r.uri.path == '/Users/viewer/Items',
            )
            .last
            .queryParameters['Is4K'],
        isTrue,
      );
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Drama');
      await key(LogicalKeyboardKey.enter);
      expect(label(), 'Drama');
      final genreQuery = requests
          .where(
            (r) =>
                r.uri.path == '/Items' || r.uri.path == '/Users/viewer/Items',
          )
          .last
          .queryParameters;
      expect(genreQuery['Genres'], 'Drama');
      expect(
        genreQuery['Is4K'],
        isNull,
        reason: 'Choosing a genre clears the previous quality filter',
      );
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'TV Shows');
      libraryOffline = true;
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(LibraryBrowseScreen), findsOneWidget);
      await key(LogicalKeyboardKey.arrowRight);
      expect(
        label(),
        'Retry',
        reason:
            'Right from the library panel reaches the failed request action',
      );
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Recently Added');
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'Retry');
      libraryOffline = false;
      await key(LogicalKeyboardKey.enter);
      expect(label(), 'TV Shows');
      await key(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'grid_item:0');
      expect(
        find.text('TV Shows'),
        findsOneWidget,
        reason: 'Retry also recovers the library list request',
      );
      expect(
        find.text('Drama'),
        findsOneWidget,
        reason: 'Retry recovers the failed genre facets too',
      );
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Library');
      await key(LogicalKeyboardKey.enter);
      expect(appRouter.routeInformationProvider.value.uri.path, '/home');
      expect(find.byType(ItemDetailScreen), findsNothing);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Home');
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(SearchScreen), findsOneWidget);
      await key(LogicalKeyboardKey.enter);
      expect(CustomTVTextField.isKeyboardVisibleNotifier.value, isTrue);
      await key(LogicalKeyboardKey.escape);
      expect(CustomTVTextField.isKeyboardVisibleNotifier.value, isFalse);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Home');
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Retro TV');
      await key(LogicalKeyboardKey.arrowDown);
      expect(label(), 'Genres');
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(AllGenresScreen), findsOneWidget);
      expect(find.byTooltip('Display Settings'), findsNothing);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(LibraryBrowseScreen), findsOneWidget);
      expect(find.text('Drama'), findsWidgets);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(
        find.text('Recently Added'),
        findsNothing,
        reason: 'A genre-scoped page must not offer global Library categories',
      );
      expect(
        requests.where((r) => r.queryParameters['GenreIds'] == 'drama'),
        isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(AllGenresScreen), findsOneWidget);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(AllGenresScreen), findsNothing);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Home');
      expect(find.text('Settings'), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-settings')), findsNothing);
      for (var step = 0; step < 6; step++) {
        await key(LogicalKeyboardKey.arrowDown);
        expect(label(), isNot('Settings'));
      }
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'Play');
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'Next');
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Play');
      await key(LogicalKeyboardKey.arrowLeft);
      expect(
        label(),
        'Home',
        reason: 'Left opens the sidebar even on a later hero slide',
      );
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'Play');
      final heroBefore = tester
          .widget<TvFeaturedHero>(find.byType(TvFeaturedHero))
          .item
          .itemId;
      await prefs.set(UserPreferences.mediaBarIntervalMs, 2000);
      await prefs.set(UserPreferences.mediaBarAutoAdvance, true);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      expect(label(), 'Details');
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester
            .widget<TvFeaturedHero>(
              find.byType(TvFeaturedHero, skipOffstage: false),
            )
            .item
            .itemId,
        heroBefore,
        reason: 'The covered Home hero must not advance behind a movie',
      );
      await prefs.set(UserPreferences.mediaBarAutoAdvance, false);
      await key(LogicalKeyboardKey.arrowUp);
      expect(label(), 'Read More');
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.enter);
      expect(
        label(),
        'Details',
        reason: 'Back restores the selected hero action',
      );
      // Mutation crosses the real Home, Favorites and detail lifetimes. The
      // server fixture actually removes the item; it cannot pass by repainting
      // a favorite icon while leaving the list and pagination stale.
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Favorites');
      await key(LogicalKeyboardKey.enter);
      expect(favorites, [heroBefore]);
      expect(
        tester.widget<TvFeaturedHero>(find.byType(TvFeaturedHero)).isFavorite,
        isTrue,
      );
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(label(), 'Home');
      for (var step = 0; step < 8 && label() != 'Favorites'; step++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(FavoritesScreen), findsOneWidget);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      for (var step = 0; step < 3; step++) {
        await key(LogicalKeyboardKey.arrowRight);
      }
      expect(label(), 'More');
      await key(LogicalKeyboardKey.enter);
      expect(find.text('Favorited'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowDown);
      favoriteResponse = Completer<void>();
      await key(LogicalKeyboardKey.enter);
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(ItemDetailScreen), findsNothing);
      // Deliver the successful removal after the detail view model has gone.
      favoriteResponse.complete();
      await settle();
      expect(favorites, isEmpty);
      expect(find.byType(ItemDetailScreen), findsNothing);
      expect(find.text('No favorites yet'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(
        label(),
        'Home',
        reason: 'Removing the last favorite must leave an exit reachable',
      );
      await key(LogicalKeyboardKey.enter);
      expect(
        tester.widget<TvFeaturedHero>(find.byType(TvFeaturedHero)).isFavorite,
        isFalse,
      );
      appRouter.go('/settings');
      await settle();
      expect(appRouter.routeInformationProvider.value.uri.path, '/home');
      expect(find.byType(SettingsSidePanel), findsNothing);
      expect(tester.takeException(), isNull);

      // The live catalogue has no alternate versions, BoxSets or folder view.
      // Exercise their real routes and remote controls against explicit data.
      appRouter.push('/item/movie-7');
      await settle();
      for (var step = 0; step < 8 && label() != 'Version'; step++) {
        await key(LogicalKeyboardKey.arrowRight);
      }
      expect(label(), 'Version');
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(TvModalPanel), findsOneWidget);
      expect(find.text('Alternate Cut'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(TvModalPanel), findsNothing);
      String? selectedVersion() => tester
          .widget<DetailActionButtons>(find.byType(DetailActionButtons))
          .selectedMediaSourceId;
      expect(selectedVersion(), 'alternate');
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.escape);
      expect(selectedVersion(), 'alternate');
      bool extraHasFocus() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<NouveauExtrasSection>() !=
          null;
      for (var step = 0; step < 12 && !extraHasFocus(); step++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      expect(extraHasFocus(), isTrue);
      await key(LogicalKeyboardKey.enter);
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId,
        'movie-8',
      );
      expect(label(), 'Play');
      await tester.binding.handlePopRoute();
      await settle();
      expect(
        extraHasFocus(),
        isTrue,
        reason: 'Back restores the selected extra',
      );
      await tester.binding.handlePopRoute();
      await settle();

      appRouter.push('/item/collection');
      await settle();
      expect(find.text('Film Collection'), findsWidgets);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId,
        'movie-4',
      );
      await tester.binding.handlePopRoute();
      await settle();
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId,
        'collection',
      );
      await tester.binding.handlePopRoute();
      await settle();

      appRouter.push('/folder/folder');
      await settle();
      expect(find.byType(FolderBrowseScreen), findsOneWidget);
      expect(find.text('Cinema'), findsWidgets);
      expect(find.text('Movies'), findsWidgets);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.enter);
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId,
        'movie-5',
      );
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(FolderBrowseScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle();
    },
  );
}
