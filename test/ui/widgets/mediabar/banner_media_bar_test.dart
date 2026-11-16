import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/bounded_network_image.dart';
import 'package:moonfin/ui/widgets/mediabar/banner_media_bar.dart';
import 'package:moonfin/ui/widgets/fullscreen_backdrop_switcher.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ViewModel extends ChangeNotifier implements MediaBarViewModel {
  _ViewModel(MediaBarSlideItem item) : items = [item];
  _ViewModel.many(this.items);

  @override
  final List<MediaBarSlideItem> items;

  @override
  MediaBarState get state => MediaBarReady(items);

  @override
  Map<String, double> ratingsFor(String itemId) => const {};

  @override
  Future<void> ensureRatings(String itemId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Issue #1265: the Banner bar shows an item's banner art where it has one,
// leaving off the title it already carries.
void main() {
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    await prefs.set(UserPreferences.mediaBarAutoAdvance, false);
  });

  tearDown(
    () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
  );

  Future<void> pumpBar(WidgetTester tester, MediaBarSlideItem item) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: BannerMediaBar(
            viewModel: _ViewModel(item),
            prefs: prefs,
            height: 240,
            onOpen: (_) {},
            onPlay: (_) {},
          ),
        ),
      ),
    );
  }

  Iterable<String> imageUrls(WidgetTester tester) => tester
      .widgetList<BoundedNetworkImage>(find.byType(BoundedNetworkImage))
      .map((image) => image.imageUrl);

  const withBanner = MediaBarSlideItem(
    itemId: 'show',
    serverId: 'server',
    title: 'The Show',
    year: 2020,
    backdropUrl: 'http://server/backdrop',
    bannerUrl: 'http://server/banner',
  );

  testWidgets('TV keeps text and actions with the decoded backdrop', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    final ready = ValueNotifier<String?>(withBanner.backdropUrl);
    addTearDown(ready.dispose);
    const next = MediaBarSlideItem(
      itemId: 'next',
      serverId: 'server',
      title: 'Next Film',
      backdropUrl: 'http://server/next',
    );
    MediaBarSlideItem? requested;
    MediaBarSlideItem? opened;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: BannerMediaBar(
            viewModel: _ViewModel.many([withBanner, next]),
            prefs: prefs,
            height: 540,
            showArtwork: false,
            artworkReady: ready,
            onCurrentItem: (item) => requested = item,
            onOpen: (item) => opened = item,
            onPlay: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Play -> Favourite -> Details -> Next.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(requested, same(next));
    expect(find.text('The Show'), findsOneWidget);
    expect(find.text('Next Film'), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(focus));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, same(withBanner));
    ready.value = next.backdropUrl;
    await tester.pumpAndSettle();
    expect(find.text('Next Film'), findsOneWidget);
    expect(find.text('The Show'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, same(next));
  });

  testWidgets('TV renders a full-width hero with actions over the backdrop', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    await pumpBar(tester, withBanner);

    expect(
      tester
          .widget<FullscreenBackdropSwitcher>(
            find.byType(FullscreenBackdropSwitcher),
          )
          .imageUrl,
      'http://server/backdrop',
    );
    expect(find.text('The Show'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a banner replaces the backdrop and the title on desktop', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    await pumpBar(tester, withBanner);

    expect(imageUrls(tester), ['http://server/banner', 'http://server/banner']);
    final whole = tester
        .widgetList<BoundedNetworkImage>(find.byType(BoundedNetworkImage))
        .where((image) => image.blurSigma == 0);
    expect(whole.single.fit, BoxFit.contain);
    expect(find.text('The Show'), findsNothing);
    expect(find.text('2020'), findsOneWidget);
  });

  testWidgets('an item without a banner keeps its backdrop and title', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    await pumpBar(
      tester,
      const MediaBarSlideItem(
        itemId: 'film',
        serverId: 'server',
        title: 'The Film',
        backdropUrl: 'http://server/backdrop',
      ),
    );

    expect(imageUrls(tester), ['http://server/backdrop']);
    expect(find.text('The Film'), findsOneWidget);
  });

  testWidgets('a phone keeps the backdrop even when there is a banner', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
    await pumpBar(tester, withBanner);

    expect(imageUrls(tester), ['http://server/backdrop']);
    expect(find.text('The Show'), findsOneWidget);
  });
}
