import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/tv/tv_reveal_transition.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin_design/moonfin_design.dart';

void main() {
  setUp(() => PlatformDetection.setInterfaceLayout(InterfaceLayout.tv));
  tearDown(
    () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
  );

  Widget screen(String name) => Scaffold(body: Center(child: Text(name)));

  Future<GoRouter> pumpRouter(WidgetTester tester, {Widget? details}) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => screen('Home')),
        GoRoute(path: '/genres', builder: (_, _) => screen('Genres')),
        GoRoute(
          path: '/item/movie',
          builder: (_, _) => details ?? screen('Movie'),
        ),
        GoRoute(
          path: '/player',
          pageBuilder: (_, _) => NoTransitionPage(child: screen('Player')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  TvRevealTransition reveal(WidgetTester tester, String text) =>
      tester.widget<TvRevealTransition>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(TvRevealTransition),
            )
            .first,
      );

  testWidgets(
    'top-level go uses the TV blur and fade through the real app theme',
    (tester) async {
      final router = await pumpRouter(tester);
      router.go('/genres');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(
        reveal(tester, 'Genres').animation.value,
        inExclusiveRange(.1, .9),
      );
      expect(
        tester
            .widget<ImageFiltered>(
              find.descendant(
                of: find
                    .ancestor(
                      of: find.text('Genres'),
                      matching: find.byType(TvRevealTransition),
                    )
                    .first,
                matching: find.byType(ImageFiltered),
              ),
            )
            .enabled,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(reveal(tester, 'Genres').animation.value, 1);
    },
  );

  testWidgets('push and Back animate both the departing and arriving screens', (
    tester,
  ) async {
    final router = await pumpRouter(tester);
    router.push('/item/movie');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    expect(reveal(tester, 'Movie').animation.value, inExclusiveRange(.1, .9));
    expect(reveal(tester, 'Home').animation.value, inExclusiveRange(.1, .9));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    expect(reveal(tester, 'Movie').animation.value, inExclusiveRange(.1, .9));
    expect(reveal(tester, 'Home').animation.value, inExclusiveRange(.1, .9));
    await tester.pumpAndSettle();
    expect(find.text('Movie'), findsNothing);
    expect(reveal(tester, 'Home').animation.value, 1);
  });

  testWidgets(
    'content arriving after the route transition still blurs and fades in',
    (tester) async {
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      final router = await pumpRouter(
        tester,
        details: ValueListenableBuilder(
          valueListenable: ready,
          builder: (_, loaded, _) => loaded
              ? const TvContentReveal(child: Text('Loaded movie'))
              : const Text('Loading'),
        ),
      );
      router.push('/item/movie');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      ready.value = true;
      await tester.pump();
      expect(reveal(tester, 'Loaded movie').animation.value, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(
        reveal(tester, 'Loaded movie').animation.value,
        inExclusiveRange(.1, .9),
      );
      await tester.pumpAndSettle();
      expect(reveal(tester, 'Loaded movie').animation.value, 1);
    },
  );

  testWidgets('fullscreen player routes keep their zero-duration transition', (
    tester,
  ) async {
    final router = await pumpRouter(tester);
    router.push('/player');
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Player'));
    expect(ModalRoute.of(context)!.transitionDuration, Duration.zero);
    expect(
      find.ancestor(
        of: find.text('Player'),
        matching: find.byType(TvRevealTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('desktop retains its existing transition theme', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    final router = await pumpRouter(tester);
    router.push('/item/movie');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TvRevealTransition), findsNothing);
    await tester.pumpAndSettle();
  });
}
