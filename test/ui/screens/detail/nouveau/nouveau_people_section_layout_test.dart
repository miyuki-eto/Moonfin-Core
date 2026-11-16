import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/nouveau/people/nouveau_people_section.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Images extends Mock implements ImageApi {}

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets('TV cast names and roles fit at text scale $scale', (
      tester,
    ) async {
      await GetIt.instance.reset();
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
      PlatformDetection.setTvMode(true);
      tester.view.physicalSize = const Size(1145, 644);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        PlatformDetection.setTvMode(false);
        tester.view.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(ThemeRegistry.active),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1048,
                child: NouveauPeopleSection(
                  actors: const [
                    {
                      'Id': 'actor',
                      'Name': 'Daniel Day-Lewis',
                      'Role': 'William Bill the Butcher Cutting',
                      'Type': 'Actor',
                    },
                  ],
                  directors: const [],
                  writers: const [],
                  imageApi: _Images(),
                  serverId: 'server',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Daniel Day-Lewis'), findsOneWidget);
      expect(find.text('William Bill the Butcher Cutting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
