import 'dart:io';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:moonfin/ui/widgets/fullscreen_backdrop_switcher.dart';
import 'package:moonfin/ui/widgets/offline_aware_image.dart';

import '../../support/artwork_fixture.dart';

class _DelayedArtwork extends FakeArtworkCacheManager {
  _DelayedArtwork(super.file);

  final ready = Completer<void>();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    if (url.contains('/next')) await ready.future;
    yield* super.getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }
}

void main() {
  group('decode bound', _decodeTests);

  Widget app(String? imageUrl) {
    return MaterialApp(
      home: FullscreenBackdropSwitcher(
        imageUrl: imageUrl,
        duration: const Duration(milliseconds: 800),
        imageBuilder: (url) => Text(url),
      ),
    );
  }

  testWidgets('decorative backdrop changes do not alter control semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app('Decorative backdrop'));
    expect(find.bySemanticsLabel('Decorative backdrop'), findsNothing);
    await tester.pumpWidget(app('Next decorative backdrop'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('Next decorative backdrop'), findsNothing);
    semantics.dispose();
  });

  testWidgets('does not restart the backdrop fade during rapid changes', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(app('c'));

    final fadeFinder = find.descendant(
      of: find.byType(FullscreenBackdropSwitcher),
      matching: find.byType(FadeTransition),
    );

    final fade = tester.widget<FadeTransition>(fadeFinder);

    expect(
      fade.opacity.value,
      greaterThan(0),
      reason: 'rapid changes should not restart the active fade from zero',
    );
  });

  testWidgets('clears all backdrop layers immediately when URL becomes null', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(app('c'));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    await tester.pumpWidget(app(null));

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(find.text('c'), findsNothing);

    final fadeFinder = find.descendant(
      of: find.byType(FullscreenBackdropSwitcher),
      matching: find.byType(FadeTransition),
    );

    expect(fadeFinder, findsNothing);
  });

  testWidgets('clears an idle backdrop with no pending transition', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    await tester.pumpWidget(app(null));
    expect(find.text('a'), findsNothing);
  });

  testWidgets('drops stale pending backdrop when focus returns to incoming', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));

    await tester.pumpAndSettle();

    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsNothing);
  });
}

void _decodeTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moonfin-switcher');
    final png = await writeTestPng(temp, width: 1920, height: 1080);
    CachedNetworkImageProvider.defaultCacheManager = FakeArtworkCacheManager(
      png,
    );
    imageCache.clear();
    ArtworkDecode.resetRememberedBounds();
  });

  tearDown(() async {
    imageCache.clear();
    await temp.delete(recursive: true);
  });

  testWidgets(
    'slow images wait to fade and cached movie artwork also fades on entry',
    (tester) async {
      final cache = _DelayedArtwork(File('${temp.path}/fixture.png'));
      CachedNetworkImageProvider.defaultCacheManager = cache;
      Widget app(String url) => MaterialApp(
        home: FullscreenBackdropSwitcher(
          imageUrl: url,
          duration: const Duration(milliseconds: 800),
          animateInitialImage: true,
        ),
      );
      final fade = find.byWidgetPredicate(
        (widget) => widget is FadeTransition && widget.child is KeyedSubtree,
      );
      double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
      Future<void> decodeUntil(int count) => tester.runAsync(() async {
        for (var i = 0; i < 50 && imageCache.currentSize < count; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(imageCache.currentSize, greaterThanOrEqualTo(count));
      });

      await tester.pumpWidget(app('http://server/first'));
      await decodeUntil(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpWidget(app('http://server/next'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        opacity(),
        0,
        reason: 'network time must not consume the transition',
      );
      expect(
        tester
            .widgetList<OfflineAwareImage>(find.byType(OfflineAwareImage))
            .map((image) => image.imageUrl),
        containsAll(['http://server/first', 'http://server/next']),
      );
      cache.ready.complete();
      await decodeUntil(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(seconds: 1));
      expect(fade, findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app('http://server/next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        opacity(),
        allOf(greaterThan(0), lessThan(1)),
        reason: 'a cache hit should still fade into movie details',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the default image path decodes a portrait cover at full width', (
    tester,
  ) async {
    // A 390 by 844 phone at 2x. A bound taken from the box width alone would
    // be 780 pixels for a backdrop that paints about 3000 wide.
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const url = 'http://server/Items/1/Images/Backdrop/0?maxWidth=1920';
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FullscreenBackdropSwitcher(
            imageUrl: url,
            duration: Duration(milliseconds: 300),
          ),
        ),
      );
      for (var i = 0; i < 25 && imageCache.currentSize == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      final key = await ArtworkDecode.provider(
        url,
        width: 1920,
      ).obtainKey(ImageConfiguration.empty);
      expect(imageCache.containsKey(key), isTrue);
      expect(imageCache.currentSize, 1);
    });
  });
}
