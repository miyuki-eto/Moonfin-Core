import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/data/viewmodels/seerr_media_detail_view_model.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/detail_section_layout.dart';
import 'package:moonfin/preference/preference_constants.dart'
    show DetailScreenStyle;
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/ui/screens/detail/nouveau/chapters/nouveau_chapters_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/details/nouveau_details_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/discovery/nouveau_discovery_rail.dart';
import 'package:moonfin/ui/screens/detail/nouveau/episodes/nouveau_episodes_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/episodes/nouveau_season_selector.dart';
import 'package:moonfin/ui/screens/detail/nouveau/hero/nouveau_action_buttons.dart';
import 'package:moonfin/ui/screens/detail/nouveau/hero/nouveau_hero.dart';
import 'package:moonfin/ui/screens/detail/nouveau/nouveau_detail_content.dart';
import 'package:moonfin/ui/screens/detail/nouveau/people/nouveau_people_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/person/nouveau_filmography_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/person/nouveau_person_content.dart';
import 'package:moonfin/ui/screens/detail/nouveau/reviews/nouveau_reviews_section.dart';
import 'package:moonfin/ui/screens/detail/nouveau/shared/nouveau_segmented_selector.dart';
import 'package:moonfin/ui/screens/detail/nouveau/shared/nouveau_landscape_media_card.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';
import 'package:moonfin/ui/tv/tv26_classification.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/rating_display.dart';
import 'package:moonfin/ui/widgets/media_card.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_item_chips.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_stats_card.dart';
import 'package:moonfin/ui/widgets/skeleton/skeleton_detail_screen.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _UserLibraryApi extends Mock implements UserLibraryApi {}

class _ImageApi extends Mock implements ImageApi {}

class _PluginSync extends Mock implements PluginSyncService {}

class _SessionRepository extends Mock implements SessionRepository {}

class _PlaybackManager extends Mock implements PlaybackManager {}

class _OfflineRepository extends Mock implements OfflineRepository {}

class _QueueService extends Mock implements QueueService {}

class _SeerrViewModel extends Mock implements SeerrMediaDetailViewModel {}

/// A real view model with the lists that need a server, or a Seerr lookup, to
/// fill handed in directly.
class _StubbedViewModel extends ItemDetailViewModel {
  _StubbedViewModel({
    required super.itemId,
    required super.client,
    required super.mutations,
    required super.mdbListRepository,
    required super.tmdbRepository,
  });

  SeerrMediaDetailViewModel? seerrOverride;
  List<AggregatedItem>? similarOverride;
  List<AggregatedItem>? filmographyOverride;
  List<TmdbReview>? reviewsOverride;
  List<AggregatedItem>? featuresOverride;
  List<AggregatedItem>? collectionOverride;
  List<AggregatedItem>? episodesOverride;
  List<AggregatedItem>? seriesEpisodesOverride;

  @override
  List<AggregatedItem> get features => featuresOverride ?? super.features;
  @override
  List<AggregatedItem> get collectionItems =>
      collectionOverride ?? super.collectionItems;
  @override
  List<AggregatedItem> get episodes => episodesOverride ?? super.episodes;
  @override
  bool get episodesLoaded => episodesOverride != null || super.episodesLoaded;
  @override
  List<AggregatedItem> get seriesEpisodes =>
      seriesEpisodesOverride ?? super.seriesEpisodes;

  @override
  SeerrMediaDetailViewModel? get seerr => seerrOverride ?? super.seerr;

  @override
  List<TmdbReview> get reviews => reviewsOverride ?? super.reviews;

  /// Hands reviews in after the page is up, the way the TMDB lookup lands.
  void deliverReviews(List<TmdbReview> reviews) {
    reviewsOverride = reviews;
    notifyListeners();
  }

  @override
  List<AggregatedItem> get similar => similarOverride ?? super.similar;

  @override
  bool get similarInitialLoadComplete =>
      similarOverride != null || super.similarInitialLoadComplete;

  @override
  List<AggregatedItem> get filmography =>
      filmographyOverride ?? super.filmography;

  List<AggregatedItem> _filmographyOf(String type) => [
    for (final item in filmography)
      if (item.type == type) item,
  ];

  @override
  List<AggregatedItem> get filmographyMovies => _filmographyOf('Movie');

  @override
  List<AggregatedItem> get filmographySeries => _filmographyOf('Series');

  @override
  List<AggregatedItem> get filmographyMusicVideos =>
      _filmographyOf('MusicVideo');

  @override
  List<AggregatedItem> get filmographyEpisodes => _filmographyOf('Episode');
}

Future<UserPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Client client;
  late _ItemsApi itemsApi;
  late _PluginSync plugin;
  late UserPreferences prefs;

  setUp(() async {
    await GetIt.instance.reset();
    client = _Client();
    itemsApi = _ItemsApi();
    prefs = await _preferences();
    final userLibrary = _UserLibraryApi();
    when(() => userLibrary.supportsNumericUserRatings).thenReturn(false);

    plugin = _PluginSync();
    when(() => plugin.seerrAvailable).thenReturn(false);
    when(() => plugin.tmdbReviewsAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(plugin);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    GetIt.instance.registerSingleton<UserRepository>(UserRepository());
    GetIt.instance.registerSingleton<PlaybackManager>(_PlaybackManager());
    GetIt.instance.registerSingleton<OfflineRepository>(_OfflineRepository());
    final playback = GetIt.instance<PlaybackManager>();
    when(() => playback.queueService).thenReturn(_QueueService());
    when(() => GetIt.instance<OfflineRepository>().getItem(any()))
        .thenAnswer((_) async => null);
    when(() => GetIt.instance<OfflineRepository>().getSeriesEpisodes(any()))
        .thenAnswer((_) async => const []);
    when(() => GetIt.instance<OfflineRepository>().getSeasonEpisodes(any()))
        .thenAnswer((_) async => const []);
    final seerrStore = PreferenceStore();
    await seerrStore.init();
    GetIt.instance.registerSingleton<SeerrPreferences>(
      SeerrPreferences(seerrStore, _SessionRepository()),
    );

    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.userLibraryApi).thenReturn(userLibrary);
    when(() => client.imageApi).thenReturn(_ImageApi());
    when(() => client.baseUrl).thenReturn('http://test-server');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    GetIt.instance.registerSingleton<RowDataSource>(RowDataSource(client));
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() => GetIt.instance.reset());

  Map<String, dynamic> itemData(
    String type, {
    String id = 'item-1',
    List<Map<String, dynamic>> chapters = const [],
    List<Map<String, dynamic>> people = const [],
  }) => {
    'Id': id,
    'Name': '$type title',
    'Type': type,
    'Overview': 'A useful detail overview',
    'Chapters': chapters,
    'People': people,
    'ProviderIds': const {},
  };

  _StubbedViewModel viewModel(String type, {Map<String, dynamic>? data}) {
    final vm = _StubbedViewModel(
      itemId: 'item-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, TmdbRepository(client)),
      tmdbRepository: TmdbRepository(client),
    );
    final raw = data ?? itemData(type);
    when(() => itemsApi.getItem('item-1')).thenAnswer((_) async => raw);
    when(
      () => itemsApi.getItem(
        'item-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer((_) async => raw);
    return vm;
  }

  Widget content(
    ItemDetailViewModel vm, {
    FocusNode? initialFocusNode,
    Size size = const Size(1200, 2200),
  }) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: AppTheme.buildTheme(ThemeRegistry.active),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: NouveauDetailContent(
          viewModel: vm,
          prefs: prefs,
          backdropUrl: ValueNotifier<String?>(null),
          selectedMediaSourceId: null,
          initialFocusNode: initialFocusNode,
          onSelectedMediaSourceChanged: (_) {},
          actionsExpanded: false,
          onActionsExpandedChanged: (_) {},
        ),
      ),
    ),
  );

  Future<void> pumpContent(
    WidgetTester tester,
    ItemDetailViewModel vm, {
    FocusNode? initialFocusNode,
    Size size = const Size(1200, 2200),
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await vm.load();
    await tester.pumpWidget(
      content(vm, initialFocusNode: initialFocusNode, size: size),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final type in ['Movie', 'BoxSet', 'Season', 'Person']) {
    testWidgets('TV $type rails share screen-edge viewport and focus gutters', (
      tester,
    ) async {
      PlatformDetection.setTvMode(true);
      tester.view.physicalSize = const Size(1145, 644);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        PlatformDetection.setTvMode(false);
        tester.view.reset();
      });
      List<AggregatedItem> items(String itemType) => List.generate(
        12,
        (index) => AggregatedItem(
          id: '$itemType-$index',
          serverId: 'server',
          rawData: {
            'Id': '$itemType-$index',
            'Name': '$itemType $index',
            'Type': itemType,
            'IndexNumber': index + 1,
            'ParentIndexNumber': 1,
          },
        ),
      );
      final vm = viewModel(
        type,
        data: itemData(
          type,
          people: [
            for (var index = 0; index < 12; index++)
              {'Id': 'person-$index', 'Name': 'Actor $index', 'Type': 'Actor'},
          ],
        ),
      );
      vm.featuresOverride = items('Video');
      vm.collectionOverride = items('Movie');
      vm.episodesOverride = items('Episode');
      vm.similarOverride = items('Movie');
      vm.filmographyOverride = items('Movie');
      vm.reviewsOverride = List.filled(8, (
        author: 'Critic',
        rating: 8.0,
        content: 'A complete review.',
        createdAt: null,
        avatarUrl: null,
        url: null,
      ));
      await pumpContent(tester, vm, size: const Size(1145, 644));
      await tester.pumpAndSettle();
      final rails = find.byWidgetPredicate(
        (widget) => widget is LockedFocusRow,
      );
      expect(
        rails,
        type == 'Person'
            ? findsOneWidget
            : findsAtLeastNWidgets(type == 'Movie' ? 4 : 1),
      );
      for (final element in rails.evaluate()) {
        final row = element.widget as LockedFocusRow;
        expect(row.viewportInsets, Tv26Style.railPadding, reason: row.hubKey);
        expect(row.paintOutset, Tv26Style.focusOutset, reason: row.hubKey);
        final mask = find.descendant(
          of: find.byWidget(row),
          matching: find.byType(ShaderMask),
        );
        final rect = tester.getRect(mask);
        final overflow = Tv26Style.focusOutset + Tv26Style.railFadeDistance;
        expect(rect.left, closeTo(-overflow, .01), reason: row.hubKey);
        expect(rect.right, closeTo(1145 + overflow, .01), reason: row.hubKey);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    });
  }

  testWidgets('TV episodes have one target and keep seasons outside the fade', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    tester.view.physicalSize = const Size(1145, 644);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      PlatformDetection.setTvMode(false);
      tester.view.reset();
    });
    final play = FocusNode();
    addTearDown(play.dispose);
    final vm = viewModel('Series');
    vm.seriesEpisodesOverride = List.generate(
      8,
      (index) => AggregatedItem(
        id: 'episode-$index',
        serverId: 'server',
        rawData: {
          'Id': 'episode-$index',
          'Name': 'Episode $index',
          'Type': 'Episode',
          'Overview': 'The episode synopsis.',
          'RunTimeTicks': 13200000000,
          'PremiereDate': '2005-08-04T00:00:00Z',
          'IndexNumber': index % 4 + 1,
          'ParentIndexNumber': index ~/ 4 + 1,
        },
      ),
    );
    vm.similarOverride = [
      AggregatedItem(
        id: 'similar',
        serverId: 'server',
        rawData: const {'Id': 'similar', 'Name': 'Similar', 'Type': 'Series'},
      ),
    ];
    await pumpContent(
      tester,
      vm,
      initialFocusNode: play,
      size: const Size(1145, 644),
    );
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    final title = find.byKey(const ValueKey('tv-scrolled-series-title'));
    double titleOpacity() => tester
        .widget<FadeTransition>(
          find.ancestor(of: title, matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;
    double heroOpacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byType(NouveauHero),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(titleOpacity(), 0);
    expect(heroOpacity(), 1);
    play.requestFocus();
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown);
    expect(titleOpacity(), 1);
    expect(heroOpacity(), 0);
    expect(tester.getCenter(title).dx, closeTo(1145 / 2, .01));
    final selector = find.byType(NouveauSeasonSelector);
    expect(
      tester.getRect(selector).top - tester.getRect(title).bottom,
      closeTo(Tv26Style.detailHeaderGap, .01),
    );
    final firstEpisode = find.byType(NouveauLandscapeMediaCard).first;
    expect(
      find.descendant(of: firstEpisode, matching: find.text('EPISODE 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstEpisode, matching: find.text('22m')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstEpisode, matching: find.text('Aug 4, 2005')),
      findsOneWidget,
    );
    expect(
      tester.getRect(firstEpisode).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byType(NouveauEpisodesSection)).bottom,
      ),
    );
    await press(LogicalKeyboardKey.arrowDown);
    final rowFocus = FocusManager.instance.primaryFocus;
    expect(
      rowFocus?.context
          ?.findAncestorWidgetOfExactType<NouveauEpisodesSection>(),
      isNotNull,
    );
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, isNot(rowFocus));
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<NouveauEpisodesSection>(),
      isNull,
    );
    await press(LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus, rowFocus);
    await press(LogicalKeyboardKey.arrowUp);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<NouveauSeasonSelector>(),
      isNotNull,
    );
    await press(LogicalKeyboardKey.arrowUp);
    expect(play.hasPrimaryFocus, isTrue);
    expect(titleOpacity(), 0);
    expect(heroOpacity(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV episode image and caption activate the same card', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    var details = 0;
    var plays = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NouveauLandscapeMediaCard(
            item: AggregatedItem(
              id: 'episode',
              serverId: 'server',
              rawData: const {
                'Id': 'episode',
                'Name': 'Episode name',
                'Type': 'Episode',
                'Overview': 'Episode synopsis',
              },
            ),
            imageUrl: null,
            width: 300,
            imageHeight: 169,
            isFocused: false,
            isNextUp: false,
            suppressArtworkFocus: false,
            onArtworkSelect: () => plays++,
            onDetailsSelect: () => details++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Episode name'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(MediaCard)));
    await tester.tap(find.text('Episode synopsis'));
    expect(details, 2);
    expect(plays, 0);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('TV episode cards omit unavailable metadata', (tester) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NouveauLandscapeMediaCard(
            item: AggregatedItem(
              id: 'episode',
              serverId: 'server',
              rawData: const {
                'Id': 'episode',
                'Name': 'Episode without metadata',
                'Type': 'Episode',
                'ProductionYear': 1999,
                'RunTimeTicks': 0,
                'PremiereDate': 'invalid',
              },
            ),
            imageUrl: null,
            width: 300,
            imageHeight: 169,
            isFocused: false,
            isNextUp: false,
            suppressArtworkFocus: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0m'), findsNothing);
    expect(find.textContaining(RegExp(r'^EPISODE \d+$')), findsNothing);
    expect(find.textContaining('1999'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV studio links use shared buttons and preserve wrapped navigation',
    (tester) async {
      PlatformDetection.setTvMode(true);
      tester.view.physicalSize = const Size(1145, 644);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        PlatformDetection.setTvMode(false);
        tester.view.reset();
      });
      final vm = viewModel(
        'Movie',
        data: {
          ...itemData('Movie'),
          'Studios': [
            {'Name': 'Studio A'},
            {'Name': 'Studio B'},
          ],
        },
      );
      await pumpContent(tester, vm, size: const Size(1145, 644));
      await tester.pumpAndSettle();
      final first = tester.widget<Tv26Button>(
        find.byWidgetPredicate((w) => w is Tv26Button && w.label == 'Studio A'),
      );
      first.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'nouveau-details-studio-1',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, first.focusNode);
      expect(tester.takeException(), isNull);
    },
  );

  Map<String, dynamic> ratedMovie({
    double? community,
    int? critic,
    double? personal,
  }) => {
    ...itemData('Movie'),
    'CommunityRating': community,
    'CriticRating': critic,
    'UserData': {'Rating': personal},
  };

  testWidgets('the hero hands its ratings to the shared row', (tester) async {
    final vm = viewModel('Movie', data: ratedMovie(community: 7.8, critic: 91));
    await pumpContent(tester, vm);

    expect(find.byType(RatingsRow), findsOneWidget);
    expect(find.text('7.8'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
  });

  testWidgets('the picker decides which sources the hero draws', (
    tester,
  ) async {
    await prefs.set(UserPreferences.enableAdditionalRatings, true);
    await prefs.set(UserPreferences.enabledRatings, 'tomatoes');

    final vm = viewModel('Movie', data: ratedMovie(community: 7.8, critic: 91));
    await pumpContent(tester, vm);

    // Community rides in as 'stars', which the picker left out.
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('7.8'), findsNothing);
  });

  testWidgets('the label and badge switches reach the hero', (tester) async {
    await prefs.set(UserPreferences.showRatingLabels, false);

    final vm = viewModel('Movie', data: ratedMovie(community: 7.8));
    await pumpContent(tester, vm);

    final row = tester.widget<RatingsRow>(find.byType(RatingsRow));
    expect(row.showLabels, isFalse);
    expect(row.showBadges, isTrue);
  });

  testWidgets('the ratings run wider than the hero text measure', (
    tester,
  ) async {
    // Comfortably past the 680 the hero's text column caps at.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);

    final vm = viewModel('Movie', data: ratedMovie(community: 7.8, critic: 91));
    await pumpContent(tester, vm, size: const Size(1920, 1080));

    final box = tester.renderObject(find.byType(RatingsRow)) as RenderBox;
    expect(box.constraints.maxWidth, greaterThan(1000));
  });

  testWidgets('a score the viewer set alone is enough to draw the row', (
    tester,
  ) async {
    final vm = viewModel('Movie', data: ratedMovie(personal: 9.0));
    await pumpContent(tester, vm);

    expect(find.byType(RatingsRow), findsOneWidget);
  });

  testWidgets('an unrated item draws no row at all', (tester) async {
    final vm = viewModel('Movie');
    await pumpContent(tester, vm);

    expect(find.byType(RatingsRow), findsNothing);
  });

  testWidgets('series and season expose episodes, movie and episode do not', (
    tester,
  ) async {
    for (final type in ['Series', 'Season']) {
      final vm = viewModel(type);
      await pumpContent(tester, vm);
      expect(
        find.byKey(const ValueKey('nouveau-section-episodes')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    for (final type in ['Movie', 'Episode']) {
      final vm = viewModel(type);
      await pumpContent(tester, vm);
      expect(
        find.byKey(const ValueKey('nouveau-section-episodes')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('TV omits chapters even when the movie has chapter data', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    await pumpContent(
      tester,
      viewModel(
        'Movie',
        data: itemData(
          'Movie',
          chapters: [
            {'StartPositionTicks': 1000, 'Name': 'Chapter one'},
          ],
        ),
      ),
    );
    expect(find.byType(NouveauChaptersSection), findsNothing);
    expect(
      find.byKey(const ValueKey('nouveau-section-chapters')),
      findsNothing,
    );
  });

  // Movie and Episode are the types that actually carry chapters, and every
  // other detail style shows them on the strength of the list alone.
  testWidgets('chapters show for any item that has them', (tester) async {
    final chapter = {'StartPositionTicks': 1000, 'Name': 'Chapter one'};
    for (final type in ['Movie', 'Episode', 'Video']) {
      await pumpContent(
        tester,
        viewModel(type, data: itemData(type, chapters: [chapter])),
      );
      expect(
        find.byKey(const ValueKey('nouveau-section-chapters')),
        findsOneWidget,
        reason: '$type carries chapters, so the section belongs on screen',
      );
    }

    await pumpContent(tester, viewModel('Video'));
    expect(
      find.byKey(const ValueKey('nouveau-section-chapters')),
      findsNothing,
    );
  });

  testWidgets('collection, extras, discovery and people use their gates', (
    tester,
  ) async {
    final people = [
      {'Name': 'Actor', 'Type': 'Actor', 'Id': 'person-1'},
    ];
    final boxSet = viewModel('BoxSet');
    await pumpContent(tester, boxSet);
    expect(
      find.byKey(const ValueKey('nouveau-section-collection')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('nouveau-section-people')), findsNothing);
    expect(find.byKey(const ValueKey('nouveau-section-extras')), findsNothing);
    expect(
      find.byKey(const ValueKey('nouveau-section-discovery')),
      findsNothing,
    );

    final movie = viewModel('Movie', data: itemData('Movie', people: people));
    await pumpContent(tester, movie);
    expect(
      find.byKey(const ValueKey('nouveau-section-people')),
      findsOneWidget,
    );
  });

  testWidgets(
    'details remain present for normal items and Person uses its own flow',
    (tester) async {
      await pumpContent(tester, viewModel('Movie'));
      expect(
        find.byKey(const ValueKey('nouveau-section-details')),
        findsOneWidget,
      );
      expect(find.text('A useful detail overview'), findsOneWidget);

      await pumpContent(tester, viewModel('Person'));
      expect(
        find.byKey(const ValueKey('nouveau-section-details')),
        findsNothing,
      );
      expect(find.byType(NouveauPersonContent), findsOneWidget);
    },
  );

  // A 1080p TV reports 960x540 logical pixels. The page pins itself to the
  // top whenever the hero has focus, so an action row below the fold is
  // unreachable rather than merely off screen.
  testWidgets('TV collections, seasons and videos are not labelled as series', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    for (final entry in {
      'BoxSet': 'Collection',
      'Season': 'Season',
      'Video': 'Video',
    }.entries) {
      await pumpContent(
        tester,
        viewModel(entry.key),
        size: const Size(1145, 644),
      );
      expect(
        find.descendant(
          of: find.byType(Tv26Classification),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: entry.key,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('TV episode details identify the selected episode', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    final vm = viewModel(
      'Episode',
      data: {
        ...itemData('Episode'),
        'Name': 'Mordland',
        'SeriesName': 'Metalocalypse',
        'ParentIndexNumber': 1,
        'IndexNumber': 9,
      },
    );
    await pumpContent(tester, vm, size: const Size(1145, 644));
    expect(find.textContaining('S1:E9 · Mordland'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the TV hero keeps its action row on screen', (tester) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));

    const tvSize = Size(960, 540);
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The badge row is off by default, but it is the tallest optional piece
    // of the hero, so it is the case that has to fit.
    await prefs.set(UserPreferences.detailShowTechnicalDetails, true);

    final vm = viewModel(
      'Movie',
      data: {
        ...itemData('Movie'),
        'Genres': const ['Horror', 'Thriller', 'Science Fiction'],
        'RunTimeTicks': 65400000000,
        'ProductionYear': 2026,
        'Overview':
            'Dr. Kelson finds himself in a shocking new relationship with '
            'consequences that could change the world as they know it and '
            'Spike encounter with Jimmy Crystal becomes a nightmare he '
            'cannot wake up from, running well past three lines of text.',
        'MediaSources': const [
          {
            'Size': 4738224128,
            'MediaStreams': [
              {'Type': 'Video', 'Height': 1080, 'Width': 1920, 'Codec': 'hevc'},
              {
                'Type': 'Audio',
                'Codec': 'eac3',
                'Profile': 'Dolby Atmos',
                'Channels': 6,
              },
            ],
          },
        ],
      },
    );
    await pumpContent(tester, vm, size: tvSize);

    final actions = tester.getRect(find.byType(NouveauActionButtons).first);
    expect(actions.bottom, lessThanOrEqualTo(tvSize.height));
  });

  // Title and overview heights vary, but the loading action baseline should
  // stay in place when the real TV hero arrives.
  testWidgets('the TV skeleton and content keep their action baseline', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));

    const tvSize = Size(960, 540);
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vm = viewModel('Movie');
    await pumpContent(tester, vm, size: tvSize);
    final contentActionBottom = tester
        .getRect(find.byType(NouveauActionButtons).first)
        .bottom;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: tvSize),
        child: MaterialApp(
          theme: AppTheme.buildTheme(ThemeRegistry.active),
          home: const Scaffold(
            body: DetailScreenSkeleton(style: DetailScreenStyle.nouveau),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final skeletonActionBottom = tester
        .getRect(find.byKey(const ValueKey('nouveau-tv-skeleton-play')))
        .bottom;

    expect(skeletonActionBottom, closeTo(contentActionBottom, 2.0));
  });

  testWidgets('null metadata and empty rails render safely', (tester) async {
    final vm = viewModel(
      'Video',
      data: {'Id': 'item-1', 'Type': 'Video', 'Name': null, 'Chapters': null},
    );
    await pumpContent(tester, vm);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('nouveau-section-details')),
      findsOneWidget,
    );
  });

  testWidgets('a book shows its file details under the Media Info setting', (
    tester,
  ) async {
    final vm = viewModel(
      'Book',
      data: {...itemData('Book'), 'Path': '/books/Dune.epub'},
    );
    await pumpContent(tester, vm);
    expect(find.text('Dune.epub'), findsOneWidget);
    expect(find.text('Format: .epub'), findsOneWidget);

    await prefs.set(detailSectionLayout.hiddenPreference, 'mediaInfo');
    await pumpContent(tester, vm);
    expect(find.text('Dune.epub'), findsNothing);
  });

  testWidgets('a book without an extension has no format line', (tester) async {
    final vm = viewModel(
      'Book',
      data: {...itemData('Book'), 'Path': '/books/Dune'},
    );
    await pumpContent(tester, vm);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.textContaining('Format:'), findsNothing);
  });

  // The screen rebuilds its content when the hidden list changes, so these
  // flip the preference and rebuild in place.
  group('hidden sections', () {
    const tvSize = Size(1920, 1080);

    late FocusNode play;

    void useTv(WidgetTester tester) {
      PlatformDetection.setTvMode(true);
      addTearDown(() => PlatformDetection.setTvMode(false));
      tester.view.physicalSize = tvSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      play = FocusNode(debugLabel: 'play');
      addTearDown(play.dispose);
    }

    Future<void> hide(
      WidgetTester tester,
      ItemDetailViewModel vm,
      String ids,
    ) async {
      await prefs.set(detailSectionLayout.hiddenPreference, ids);
      await tester.pumpWidget(
        content(vm, initialFocusNode: play, size: tvSize),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    bool focusIn<T extends Widget>() {
      final context = FocusManager.instance.primaryFocus?.context;
      return context?.findAncestorWidgetOfExactType<T>() != null;
    }

    Future<void> focusPlay(WidgetTester tester) async {
      play.requestFocus();
      await tester.pump();
      expect(play.hasPrimaryFocus, isTrue);
    }

    // A lookup that landed with nothing the viewer can request or report.
    _SeerrViewModel seerrWith(SeerrMediaDetailState state) {
      final seerr = _SeerrViewModel();
      when(() => seerr.state).thenReturn(state);
      when(() => seerr.relatedLoadComplete).thenReturn(true);
      when(() => seerr.canRequest).thenReturn(false);
      when(() => seerr.canRequest4k).thenReturn(false);
      when(() => seerr.canRequestAdvanced).thenReturn(false);
      when(() => seerr.canManageRequests).thenReturn(false);
      when(() => seerr.canReportIssue).thenReturn(false);
      return seerr;
    }

    final actor = {'Name': 'Actor', 'Type': 'Actor', 'Id': 'person-1'};
    final chapter = {'StartPositionTicks': 1000, 'Name': 'Chapter one'};

    testWidgets('a hidden section leaves the chain and Down skips it', (
      tester,
    ) async {
      useTv(tester);
      final vm = viewModel(
        'Movie',
        data: {
          ...itemData('Movie', chapters: [chapter], people: [actor]),
          'Studios': const [
            {'Name': 'Studio One', 'Id': 'studio-1'},
          ],
        },
      );
      await pumpContent(tester, vm, initialFocusNode: play, size: tvSize);

      await focusPlay(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauPeopleSection>(), isTrue);
      expect(
        find.byKey(const ValueKey('nouveau-section-chapters')),
        findsNothing,
      );

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauDetailsSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusIn<NouveauPeopleSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(play.hasPrimaryFocus, isTrue);

      // Cast was the only thing in the people rail, so it goes as a whole.
      await hide(tester, vm, 'cast');
      expect(
        find.byKey(const ValueKey('nouveau-section-people')),
        findsNothing,
      );

      await focusPlay(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauDetailsSection>(), isTrue);
    });

    testWidgets('reviews join the chain when they land after the page', (
      tester,
    ) async {
      useTv(tester);
      const TmdbReview review = (
        author: 'Critic',
        rating: 8.0,
        content: 'Loved it.',
        createdAt: null,
        avatarUrl: null,
        url: null,
      );
      final vm = viewModel('Movie', data: itemData('Movie', people: [actor]));
      await pumpContent(tester, vm, initialFocusNode: play, size: tvSize);
      expect(find.byType(NouveauReviewsSection), findsNothing);

      vm.deliverReviews(const [review, review]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('nouveau-section-reviews')),
        findsOneWidget,
      );

      await focusPlay(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauReviewsSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusIn<NouveauReviewsSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauPeopleSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusIn<NouveauReviewsSection>(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(play.hasPrimaryFocus, isTrue);

      await hide(tester, vm, 'reviews');
      expect(find.byType(NouveauReviewsSection), findsNothing);

      await focusPlay(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauPeopleSection>(), isTrue);
    });

    testWidgets('a details section with every group hidden leaves the chain', (
      tester,
    ) async {
      useTv(tester);
      final seerr = seerrWith(
        const SeerrMediaDetailState(
          movie: SeerrMovieDetails(
            id: 603,
            title: 'Movie title',
            status: 'Released',
            voteAverage: 8.1,
            genres: [SeerrGenre(id: 28, name: 'Action')],
          ),
          similar: [SeerrDiscoverItem(id: 604, title: 'Sequel')],
        ),
      );

      final vm = viewModel(
        'Movie',
        data: {
          ...itemData('Movie', people: [actor]),
          'Studios': const [
            {'Name': 'Studio One', 'Id': 'studio-1'},
          ],
          'MediaSources': const [
            {
              'Id': 'source-1',
              'Path': '/media/movie.mkv',
              'Container': 'mkv',
              'MediaStreams': [
                {'Type': 'Video', 'Codec': 'hevc'},
              ],
            },
          ],
        },
      )..seerrOverride = seerr;
      await pumpContent(tester, vm, initialFocusNode: play, size: tvSize);

      final details = tester.state<NouveauDetailsSectionState>(
        find.byType(NouveauDetailsSection),
      );
      expect(find.text('Studio One'), findsOneWidget);
      expect(find.byType(SeerrItemChips), findsOneWidget);
      expect(find.byType(SeerrStatsCard), findsOneWidget);
      expect(details.canFocusTop, isTrue);

      // The reading node was mounted for the stats and the file details, and
      // keeps its context after they go, which used to keep it in the chain.
      await hide(tester, vm, 'studios,seerrGenresTags,seerrStats,mediaInfo');
      expect(find.text('Studio One'), findsNothing);
      expect(find.byType(SeerrItemChips), findsNothing);
      expect(find.byType(SeerrStatsCard), findsNothing);
      expect(details.canFocusTop, isFalse);

      await focusPlay(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauPeopleSection>(), isTrue);

      // The people rail is the last stop now, so Down stays put.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIn<NouveauPeopleSection>(), isTrue);
    });

    testWidgets(
      'hidden Seerr recommendations stop stripping the related rail',
      (tester) async {
        when(() => plugin.seerrAvailable).thenReturn(true);

        AggregatedItem library(int index, {int? tmdb, String? name}) =>
            AggregatedItem(
              id: 'similar-$index',
              serverId: 'server',
              rawData: {
                'Id': 'similar-$index',
                'Name': name ?? 'Similar $index',
                'Type': 'Movie',
                'ProductionYear': 2000 + index,
                'ProviderIds': {'Tmdb': '${tmdb ?? 200 + index}'},
              },
            );

        // The first seven are the protected head of the rail. The two after it
        // are the tail, and one of them is also a Seerr recommendation.
        final similar = [
          for (var i = 0; i < 7; i++) library(i),
          library(7, tmdb: 900, name: 'Shared pick'),
          library(8),
        ];

        final seerr = seerrWith(
          const SeerrMediaDetailState(
            movie: SeerrMovieDetails(id: 100, title: 'Movie title'),
            recommendations: [
              SeerrDiscoverItem(id: 900, mediaType: 'movie', title: 'Shared'),
              SeerrDiscoverItem(id: 901, mediaType: 'movie', title: 'Both'),
            ],
            similar: [
              SeerrDiscoverItem(id: 901, mediaType: 'movie', title: 'Both'),
              SeerrDiscoverItem(
                id: 902,
                mediaType: 'movie',
                title: 'Only here',
              ),
            ],
          ),
        );

        final vm =
            viewModel(
                'Movie',
                data: {
                  ...itemData('Movie'),
                  'ProviderIds': const {'Tmdb': '100'},
                },
              )
              ..similarOverride = similar
              ..seerrOverride = seerr;
        await pumpContent(tester, vm);

        List<List<String>> rails() => [
          for (final rail in tester.widgetList<NouveauDiscoveryRail>(
            find.byType(NouveauDiscoveryRail),
          ))
            [for (final item in rail.items) item.id],
        ];

        final head = [for (var i = 0; i < 7; i++) 'similar-$i'];

        expect(rails(), [
          [...head, 'similar-8', '902'],
          ['900', '901'],
        ]);

        await prefs.set(
          detailSectionLayout.hiddenPreference,
          'seerrRecommendations',
        );
        await tester.pumpWidget(content(vm));
        await tester.pump(const Duration(milliseconds: 500));

        expect(rails(), [
          [...head, 'similar-7', 'similar-8', '901', '902'],
        ]);
      },
    );

    testWidgets('person tabs and the All fallback leave hidden credits out', (
      tester,
    ) async {
      AggregatedItem credit(String id, String type, {String? seriesId}) =>
          AggregatedItem(
            id: id,
            serverId: 'server',
            rawData: {
              'Id': id,
              'Name': 'Credit $id',
              'Type': type,
              'SeriesId': ?seriesId,
            },
          );

      List<String> tabs() {
        final selector = tester.widget<NouveauSegmentedSelector<Object?>>(
          find.byWidgetPredicate((w) => w is NouveauSegmentedSelector),
        );
        return [for (final tab in selector.values) (tab as Enum).name];
      }

      List<String> rail() => [
        for (final item
            in tester
                .widget<NouveauFilmographySection>(
                  find.byType(NouveauFilmographySection),
                )
                .items)
          item.id,
      ];

      final vm =
          viewModel(
              'Person',
              data: {
                ...itemData('Person'),
                'ProductionLocations': const ['Springfield'],
              },
            )
            ..filmographyOverride = [
              credit('movie-1', 'Movie'),
              credit('guest-1', 'Episode', seriesId: 'someone-elses-show'),
              credit('video-1', 'MusicVideo'),
            ];
      await pumpContent(tester, vm);

      expect(tabs(), ['movies', 'guestAppearances', 'musicVideos']);
      expect(find.text('A useful detail overview'), findsOneWidget);
      expect(find.text('Springfield'), findsOneWidget);

      await prefs.set(
        detailSectionLayout.hiddenPreference,
        'guestAppearances,musicVideos,biography,birthplace',
      );
      await tester.pumpWidget(content(vm));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tabs(), ['movies']);
      expect(find.text('A useful detail overview'), findsNothing);
      expect(find.text('Springfield'), findsNothing);

      // Without the movie nothing visible is left, and the All tab used to
      // bring every credit back. It keeps only what no switch covers.
      vm.filmographyOverride = [
        credit('guest-1', 'Episode', seriesId: 'someone-elses-show'),
        credit('video-1', 'MusicVideo'),
        credit('trailer-1', 'Trailer'),
      ];
      await tester.pumpWidget(content(vm));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tabs(), ['all']);
      expect(rail(), ['trailer-1']);

      vm.filmographyOverride = [
        credit('guest-1', 'Episode', seriesId: 'someone-elses-show'),
        credit('video-1', 'MusicVideo'),
      ];
      await tester.pumpWidget(content(vm));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byWidgetPredicate((w) => w is NouveauSegmentedSelector),
        findsNothing,
      );
      expect(
        tester
            .state<NouveauPersonContentState>(find.byType(NouveauPersonContent))
            .canFocusTop,
        isFalse,
      );
    });
  });
}
