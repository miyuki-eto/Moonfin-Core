import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/fullscreen_backdrop_switcher.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/mediabar/tv_featured_hero.dart';

void main() {
  const movie = MediaBarSlideItem(
    itemId: 'movie',
    serverId: 'server',
    title: 'A Film',
    overview: 'A useful synopsis of the film.',
    backdropUrl: 'http://server/backdrop',
    bannerUrl: 'http://server/banner',
    genres: ['Drama'],
    year: 2025,
  );

  Future<void> pumpHero(
    WidgetTester tester, {
    MediaBarSlideItem item = movie,
    int count = 3,
    VoidCallback? onPlay,
    VoidCallback? onOpen,
    VoidCallback? onNext,
    VoidCallback? onDown,
    FocusNode? focusNode,
  }) async {
    tester.view.physicalSize = const Size(1150, 647);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: TvFeaturedHero(
            item: item,
            height: 647 * 0.8,
            index: 0,
            count: count,
            focusNode: focusNode,
            onPlay: onPlay ?? () {},
            onOpen: onOpen ?? () {},
            onPrevious: () {},
            onNext: onNext ?? () {},
            onNavigateDown: onDown,
            onFocusChange: (_) {},
            onHoverChange: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'TV uses backdrop art with readable title, synopsis and real actions',
    (tester) async {
      await pumpHero(tester);
      final images = tester.widgetList<FullscreenBackdropSwitcher>(
        find.byType(FullscreenBackdropSwitcher),
      );
      expect(images.map((image) => image.imageUrl), ['http://server/backdrop']);
      expect(find.text('A Film'), findsOneWidget);
      expect(find.text(movie.overview!), findsOneWidget);
      expect(tester.getRect(find.text('Play')).bottom, lessThan(647 * 0.8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remote crosses Play, Details and Next without activating the wrong action',
    (tester) async {
      var plays = 0;
      var opens = 0;
      var next = 0;
      var down = 0;
      await pumpHero(
        tester,
        onPlay: () => plays++,
        onOpen: () => opens++,
        onNext: () => next++,
        onDown: () => down++,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(plays, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 1);
      expect(plays, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(next, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(down, 1);
    },
  );

  testWidgets(
    'Home keeps ownership of focus while moving between hero actions',
    (tester) async {
      final slot = FocusNode();
      addTearDown(slot.dispose);
      var opens = 0;
      await pumpHero(tester, focusNode: slot, onOpen: () => opens++);
      slot.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(slot.hasFocus, isTrue);
      expect(slot.hasPrimaryFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(slot.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 1);
    },
  );

  testWidgets(
    'one external title keeps focus on Details and never offers Play',
    (tester) async {
      var opens = 0;
      var plays = 0;
      await pumpHero(
        tester,
        item: const MediaBarSlideItem(
          itemId: 'external',
          serverId: MediaBarSlideItem.externalServerId,
          title: 'Upcoming Film',
        ),
        count: 1,
        onOpen: () => opens++,
        onPlay: () => plays++,
      );
      expect(find.text('Play'), findsNothing);
      expect(find.byType(Tv26Button), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opens, 1);
      expect(plays, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
