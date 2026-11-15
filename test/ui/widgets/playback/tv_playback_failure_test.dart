import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/playback/tv_playback_failure.dart';

void main() {
  testWidgets('failed playback keeps Retry and Back reachable by remote', (
    tester,
  ) async {
    var retries = 0;
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: TvPlaybackFailure(
            message: 'Playback failed.',
            onRetry: () => retries++,
            onBack: () => backs++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<Tv26Button>()
        ?.label;
    expect(focused(), 'Retry');
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(focused(), 'Retry');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(retries, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focused(), 'Back');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(), 'Retry');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(backs, 1);
    expect(tester.takeException(), isNull);
  });
}
