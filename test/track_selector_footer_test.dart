import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin/ui/tv/tv_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/track_selector_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _footerKey = Key('delay-footer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Future<void> openSelector(WidgetTester tester, int trackCount) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => TrackSelectorDialog.show(
              context,
              title: 'Subtitle track',
              options: [
                for (var i = 0; i < trackCount; i++)
                  TrackOption(label: 'Track $i'),
              ],
              footer: const SizedBox(
                key: _footerKey,
                height: 120,
                child: Text('Subtitle delay'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV selected track owns attached focus and arrows move between rows',
    (tester) async {
      PlatformDetection.setTvMode(true);
      await openSelector(tester, 3);
      final panel = tester.getRect(find.byType(TvModalPanel));
      final cancel = tester.getRect(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(TvMenuRow),
        ),
      );
      expect(cancel.left - panel.left, closeTo(8, .01));
      expect(panel.right - cancel.right, closeTo(8, .01));
      expect(panel.bottom - cancel.bottom, closeTo(8, .01));
      final row = find.ancestor(
        of: find.text('Track 0'),
        matching: find.byType(TvMenuRow),
      );
      final focus = tester.widget<Focus>(
        find.descendant(of: row, matching: find.byType(Focus)).first,
      );
      expect(focus.focusNode?.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final next = find.ancestor(
        of: find.text('Track 1'),
        matching: find.byType(TvMenuRow),
      );
      final nextFocus = tester.widget<Focus>(
        find.descendant(of: next, matching: find.byType(Focus)).first,
      );
      expect(nextFocus.focusNode?.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('a long list keeps the footer past its last track', (
    tester,
  ) async {
    await openSelector(tester, 40);

    final scrollable = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Scrollable),
    );
    expect(find.byKey(_footerKey).hitTestable(), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(_footerKey),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_footerKey).hitTestable(), findsOneWidget);
    expect(find.text('Track 39'), findsOneWidget);
  });

  testWidgets('a short list still shows the footer without scrolling', (
    tester,
  ) async {
    await openSelector(tester, 2);

    expect(find.byKey(_footerKey).hitTestable(), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
  });
}
