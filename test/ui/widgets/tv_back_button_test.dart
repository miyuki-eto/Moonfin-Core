import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/tv/tv_back_button.dart';
import 'package:moonfin/ui/widgets/focus/focusable_wrapper.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester, {String initial = '/home'}) async {
    final node = FocusNode();
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('Home catalogue')),
        GoRoute(
          path: '/item/film',
          builder: (_, _) => Scaffold(
            body: TvBackButton(focusNode: node, onExitToContent: () {}),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('visible Back returns to the previous screen with the remote', (
    tester,
  ) async {
    final router = await pump(tester);
    router.push('/item/film');
    await tester.pumpAndSettle();
    final back = tester.widget<TvBackButton>(find.byType(TvBackButton));
    back.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Home catalogue'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('a directly opened movie still has a route back to Home', (
    tester,
  ) async {
    await pump(tester, initial: '/item/film');
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Home catalogue'), findsOneWidget);
  });
  testWidgets('Back Select release does not reopen the restored episode card', (
    tester,
  ) async {
    final episode = FocusNode(debugLabel: 'episodeDescription');
    final back = FocusNode(debugLabel: 'episodeBack');
    addTearDown(episode.dispose);
    addTearDown(back.dispose);
    late GoRouter router;
    var opened = 0;
    router = GoRouter(
      initialLocation: '/series',
      routes: [
        GoRoute(
          path: '/series',
          builder: (context, _) => Scaffold(
            body: FocusableWrapper(
              focusNode: episode,
              enableLongPress: true,
              onLongPress: () {},
              onSelect: () {
                opened++;
                router.push('/episode');
              },
              child: const Text('Episode description'),
            ),
          ),
        ),
        GoRoute(
          path: '/episode',
          builder: (context, _) => Scaffold(
            body: TvBackButton(focusNode: back, onExitToContent: () {}),
          ),
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
    episode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
    back.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    episode.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      opened,
      1,
      reason: 'Only the Back button received this Select key-down',
    );
    expect(find.text('Episode description'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });
}
