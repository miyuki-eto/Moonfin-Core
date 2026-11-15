import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:moonfin/ui/screens/home/tv_home_content.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/tv/tv_card_focus_frame.dart';
import 'package:moonfin/ui/widgets/focus/locked_focus_row.dart';
import 'package:moonfin/ui/widgets/mediabar/tv_featured_hero.dart';
import 'package:moonfin/ui/widgets/startup_loading.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';
import 'package:moonfin/ui/tv/tv_reveal_transition.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/artwork_fixture.dart';

class _HeldArtwork extends FakeArtworkCacheManager {
  _HeldArtwork(super.file);
  final released = Completer<void>();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    await released.future;
    yield* super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }
}

class _Featured extends ChangeNotifier implements MediaBarViewModel {
  bool loading = false;
  bool empty = false;
  String? artworkUrl;
  MediaBarState? stateOverride;
  int retries = 0;
  @override
  Future<void> load({
    BuildContext? context,
    bool preserveCurrent = true,
    bool force = false,
  }) async {
    retries++;
  }

  @override
  List<MediaBarSlideItem> get items => loading || empty
      ? const []
      : [
          MediaBarSlideItem(
            itemId: 'featured',
            serverId: 'server',
            title: 'Featured',
            backdropUrl: artworkUrl,
          ),
        ];
  @override
  MediaBarState get state =>
      stateOverride ??
      (loading ? const MediaBarLoading() : MediaBarReady(items));

  void finishLoading() {
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> ensureRatings(String itemId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HomeRow _row(
  String id, {
  HomeRowType type = HomeRowType.latestMedia,
  bool loading = false,
}) => HomeRow(
  id: id,
  title: id,
  rowType: type,
  isLoading: loading,
  items: loading
      ? const []
      : [
          AggregatedItem(
            id: '$id-film',
            serverId: 'server',
            rawData: {'Name': '$id film', 'Type': 'Movie'},
          ),
        ],
);

class _Home extends ChangeNotifier implements HomeViewModel {
  _Home(this.rows);
  @override
  List<HomeRow> rows;
  @override
  bool isLoading = false;
  @override
  final _Featured mediaBarViewModel = _Featured();
  @override
  bool get hasDeferredSections => rows.any((row) => row.isLoading);
  int refreshes = 0;
  VoidCallback? onRefresh;
  @override
  Future<void> refresh({
    bool preserveExisting = true,
    bool newMediaBar = false,
    bool newSectionsOnly = false,
  }) async {
    refreshes++;
    onRefresh?.call();
  }

  final loaded = <String>[];
  void deliverRows(List<HomeRow> rows) {
    this.rows = rows;
    isLoading = false;
    notifyListeners();
  }

  @override
  void loadSectionsNear(Iterable<HomeRow> nearRows) {
    final due = nearRows
        .where((row) => row.isLoading)
        .map((row) => row.id)
        .toSet();
    if (due.isEmpty) return;
    loaded.addAll(due);
    rows = [
      for (final row in rows)
        if (due.contains(row.id)) _row(row.id) else row,
    ];
    notifyListeners();
  }

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

void main() {
  late UserPreferences prefs;
  setUp(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    await prefs.set(UserPreferences.mediaBarAutoAdvance, false);
  });
  tearDown(
    () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
  );

  Future<void> pump(
    WidgetTester tester,
    _Home vm, {
    void Function(HomeRow, AggregatedItem)? onOpen,
    Widget Function(Widget)? pageBuilder,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1145, 644);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: TvHomeContent(
            viewModel: vm,
            prefs: prefs,
            imageUrl: (_) => null,
            onItemSelected: (_) {},
            onOpenItem: onOpen ?? (_, _) {},
            onItemMenu: (_, _) {},
            pageBuilder: pageBuilder,
          ),
        ),
      ),
    );
    await tester.pump();
    if (vm.isLoading || !settle) {
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'remote centres the first and final Home rows outside edge fades',
    (tester) async {
      final vm = _Home([_row('Movies'), _row('Shows'), _row('Final')]);
      await pump(tester, vm);
      for (final label in ['Movies', 'Shows', 'Final']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
        final row = find.byWidgetPredicate(
          (w) =>
              w is LockedFocusRow<AggregatedItem> &&
              w.focusNode?.debugLabel == label,
        );
        final rect = tester.getRect(row);
        expect(rect.center.dy, closeTo(322, 30));
        expect(rect.top, greaterThan(160));
      }
    },
  );

  testWidgets('global Back returns a scrolled Home to its hero first', (
    tester,
  ) async {
    final vm = _Home([_row('Movies'), _row('Shows')]);
    await pump(tester, vm);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Movies');
    expect(InlineBackInterceptor.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<Tv26Button>()
          ?.label,
      'Play',
    );
    expect(InlineBackInterceptor.handleBack(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final timesOut in [false, true]) {
    testWidgets(
      'Home and navigation reveal after delayed artwork (timeout=$timesOut)',
      (tester) async {
        final fixture = (await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('home-entrance');
          return (
            dir: dir,
            file: await writeTestPng(dir, width: 400, height: 225),
          );
        }))!;
        final cache = _HeldArtwork(fixture.file);
        CachedNetworkImageProvider.defaultCacheManager = cache;
        addTearDown(() async {
          PaintingBinding.instance.imageCache.clear();
          await tester.runAsync(() => fixture.dir.delete(recursive: true));
        });
        final vm = _Home([])..isLoading = true;
        vm.mediaBarViewModel
          ..loading = true
          ..artworkUrl = 'http://home-entrance.test/hero';
        await pump(
          tester,
          vm,
          settle: false,
          pageBuilder: (content) => Stack(
            children: [
              content,
              const Positioned(left: 20, top: 20, child: Text('Navigation')),
            ],
          ),
        );
        final loaderState = tester.state(find.byType(StartupLoading));
        expect(find.text('Navigation'), findsNothing);
        vm.mediaBarViewModel.finishLoading();
        vm.deliverRows([_row('Movies')]);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(tester.state(find.byType(StartupLoading)), same(loaderState));
        final page = find.byType(TvContentReveal);
        final transition = find
            .descendant(of: page, matching: find.byType(TvRevealTransition))
            .first;
        expect(
          tester.widget<TvRevealTransition>(transition).animation.value,
          0,
          reason: 'Network time must not consume the page entrance',
        );
        expect(
          find.descendant(of: page, matching: find.text('Navigation')),
          findsOneWidget,
        );
        if (timesOut) {
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          await tester.pump(AppMotion.screen);
          expect(find.byType(StartupLoading), findsNothing);
          expect(
            tester.widget<TvRevealTransition>(transition).animation.value,
            1,
          );
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'featuredPlay',
          );
        }
        cache.released.complete();
        for (
          var i = 0;
          i < 30 &&
              (PaintingBinding.instance.imageCache.currentSize == 0 ||
                  (!timesOut &&
                      find.byType(StartupLoading).evaluate().isNotEmpty));
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byType(StartupLoading), findsNothing);
        if (timesOut) {
          expect(
            tester.widget<TvRevealTransition>(transition).animation.value,
            1,
            reason: 'Late artwork must not replay the page entrance',
          );
          final artworkReveal = find.descendant(
            of: find.byType(TvFeaturedArtwork),
            matching: find.byType(TvRevealTransition),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 225));
          expect(
            tester.widget<TvRevealTransition>(artworkReveal).animation.value,
            inExclusiveRange(0, 1),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          return;
        }
        expect(
          tester.widget<TvRevealTransition>(transition).animation.value,
          0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 225));
        expect(
          tester.widget<TvRevealTransition>(transition).animation.value,
          inExclusiveRange(0, 1),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TvRevealTransition>(transition).animation.value,
          1,
        );
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'featuredPlay');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final heroFirst in [true, false]) {
    testWidgets(
      'cold Home waits for real rows and hero, then fades once (heroFirst=$heroFirst)',
      (tester) async {
        final vm = _Home([])..isLoading = true;
        vm.mediaBarViewModel.loading = true;
        await pump(tester, vm);
        expect(find.byType(StartupLoading), findsOneWidget);
        if (heroFirst) {
          vm.mediaBarViewModel.finishLoading();
        } else {
          vm.deliverRows([_row('Movies')]);
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byType(StartupLoading),
          findsOneWidget,
          reason:
              'there must be no placeholder Home followed by another loader',
        );
        if (heroFirst) {
          vm.deliverRows([_row('Movies')]);
        } else {
          vm.mediaBarViewModel.finishLoading();
        }
        await tester.pump();
        expect(find.byType(StartupLoading), findsNothing);
        final entrance = find.byType(TvContentReveal);
        final fade = find
            .descendant(of: entrance, matching: find.byType(TvRevealTransition))
            .first;
        expect(tester.widget<TvRevealTransition>(fade).animation.value, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 225));
        expect(
          tester.widget<TvRevealTransition>(fade).animation.value,
          inExclusiveRange(0, 1),
        );
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'featuredPlay');
        vm.isLoading = true;
        vm.notifyListeners();
        await tester.pump();
        expect(
          find.byType(StartupLoading),
          findsNothing,
          reason: 'background refresh must keep the usable Home on screen',
        );
        expect(tester.widget<TvRevealTransition>(fade).animation.value, 1);
      },
    );
  }

  for (final disabled in [false, true]) {
    testWidgets('empty Home has a remote retry (disabled=$disabled)', (
      tester,
    ) async {
      final vm = _Home([]);
      vm.mediaBarViewModel.empty = true;
      if (disabled) {
        vm.mediaBarViewModel.stateOverride = const MediaBarDisabled();
      }
      await pump(tester, vm);
      expect(find.byType(StartupLoading), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Tv26Button>()
            ?.label,
        'Refresh',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(vm.refreshes, 1);
      vm.onRefresh = () => vm.deliverRows([_row('Movies')]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Movies',
        reason: 'A successful retry lands on the first real card',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home without featured items starts on a real row', (
    tester,
  ) async {
    final vm = _Home([_row('Movies')]);
    vm.mediaBarViewModel.empty = true;
    vm.mediaBarViewModel.stateOverride = const MediaBarDisabled();
    await pump(tester, vm);
    expect(find.byType(StartupLoading), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Movies');
    expect(tester.getTopLeft(find.text('Movies')).dy, lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed featured load exposes remote retry without a second loader',
    (tester) async {
      final vm = _Home([_row('Movies')]);
      vm.mediaBarViewModel.empty = true;
      vm.mediaBarViewModel.stateOverride = const MediaBarError('Unavailable');
      await pump(tester, vm);
      expect(find.byType(StartupLoading), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(vm.mediaBarViewModel.retries, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Movies');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home keeps the reference first fold and remote returns from its real row',
    (tester) async {
      final vm = _Home([
        _row('Recently Added'),
        _row('resume', type: HomeRowType.resume),
      ]);
      AggregatedItem? opened;
      await pump(tester, vm, onOpen: (_, item) => opened = item);
      final play = find.byWidgetPredicate(
        (w) => w is Tv26Button && w.label == 'Play',
      );
      expect(tester.getRect(play), const Rect.fromLTWH(45, 423, 137, 40));
      expect(tester.getTopLeft(find.text('Continue Watching')).dy, 524);
      final firstRow = find.byType(LockedFocusRow<AggregatedItem>).first;
      expect(
        tester.getTopLeft(firstRow).dy,
        closeTo(
          tester.getRect(find.text('Continue Watching')).bottom +
              Tv26Style.railTitleGap,
          1,
        ),
      );
      expect(
        tester.widget<TvFeaturedHero>(find.byType(TvFeaturedHero)).showArtwork,
        isFalse,
      );
      expect(find.byType(TvFeaturedArtwork), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TvCardFocusFrame>(find.byType(TvCardFocusFrame))
            .where((frame) => frame.focused),
        hasLength(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened?.id, 'resume-film');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Continue Watching')).dy, 524);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'featuredPlay');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Back restores the same title after Continue Watching reorders', (
    tester,
  ) async {
    final resume = _row('resume', type: HomeRowType.resume);
    final first = resume.items.single;
    final second = _row('other').items.single;
    final row = resume.copyWith(items: [first, second]);
    final vm = _Home([row]);
    final opened = <String>[];
    await pump(
      tester,
      vm,
      onOpen: (_, item) {
        opened.add(item.id);
        final context = tester.element(find.byType(TvHomeContent));
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Details')),
          ),
        );
      },
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);

    vm.deliverRows([
      row.copyWith(items: [second, first]),
    ]);
    await tester.pump();
    Navigator.of(tester.element(find.text('Details'))).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(opened, [second.id, second.id]);
  });

  testWidgets(
    'scrolling reaches deferred sections without fetching every row at mount',
    (tester) async {
      final vm = _Home([
        for (var i = 0; i < 20; i++) _row('row$i', loading: i >= 8),
      ]);
      await pump(tester, vm);
      expect(vm.loaded, isEmpty);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(vm.loaded, isNotEmpty);
      expect(vm.loaded, isNot(contains('row19')));
      expect(tester.takeException(), isNull);
    },
  );
}
