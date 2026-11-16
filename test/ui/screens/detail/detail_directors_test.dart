import 'package:flutter/material.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/detail/detail_directors.dart';

void main() {
  testWidgets('director links keep server context and accept D-pad handoffs', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var up = 0;
    var down = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: DetailDirectors(
              serverId: 'local-server',
              directors: const [
                {'Name': 'Credit without a profile'},
                {'Name': 'Ridley Scott', 'Id': 'ridley'},
                {'Name': 'Tony Scott', 'Id': 'tony'},
                {'Name': '  ', 'Id': 'empty'},
              ],
              firstFocusNode: focus,
              onNavigateUp: () => up++,
              onNavigateDown: () => down++,
            ),
          ),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              '${state.pathParameters['id']} on ${state.uri.queryParameters['serverId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Tv26Button), findsNWidgets(2));
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect([up, down], [1, 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('ridley on local-server'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Ridley Scott'), findsOneWidget);
  });
}
