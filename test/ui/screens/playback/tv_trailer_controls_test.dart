import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/playback/widgets/tv_trailer_controls.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';

void main() {
  testWidgets(
    'remote reaches seek controls and Back, hiding retains pause access',
    (tester) async {
      var paused = false;
      var exits = 0;
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TvTrailerControls(
                paused: paused,
                onTogglePause: () => setState(() => paused = !paused),
                onSeek: seeks.add,
                onBack: () => exits++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      bool focused(String label) => tester
          .widget<Tv26Button>(
            find.byWidgetPredicate((w) => w is Tv26Button && w.label == label),
          )
          .focusNode!
          .hasFocus;
      expect(focused('Pause'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(seeks, [
        const Duration(seconds: -10),
        const Duration(seconds: 10),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused('Back'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(paused, isTrue);
      expect(focused('Play'), isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(exits, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(exits, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
