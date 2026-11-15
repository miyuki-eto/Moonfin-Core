import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/tv/tv_text_dialog.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'long synopsis scrolls with arrows and dismissal restores its opener',
    (tester) async {
      PlatformDetection.setTvMode(true);
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
      final opener = FocusNode();
      addTearDown(() async {
        opener.dispose();
        PlatformDetection.setTvMode(false);
        await GetIt.instance.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Tv26Button(
                  label: 'Read More',
                  focusNode: opener,
                  autofocus: true,
                  onPressed: () => showTvTextDialog(
                    context,
                    title: 'Overview',
                    text: List.filled(100, 'A long movie synopsis.').join('\n'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(opener.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
