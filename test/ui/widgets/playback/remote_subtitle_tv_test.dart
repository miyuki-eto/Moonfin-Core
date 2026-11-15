import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/ui/widgets/playback/track_picker.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Items extends Fake implements ItemsApi {
  bool fail = false;
  bool empty = false;
  int searches = 0;
  int downloads = 0;
  @override
  Future<List<Map<String, dynamic>>> searchRemoteSubtitles(
    String itemId, {
    required String language,
    bool? isPerfectMatch,
  }) async {
    searches++;
    if (fail) throw StateError('Subtitle provider unavailable');
    return empty
        ? []
        : [
            {'Id': 'sub-1', 'Name': 'English subtitles'},
          ];
  }

  @override
  Future<void> downloadRemoteSubtitle(String itemId, String subtitleId) async {
    downloads++;
  }
}

class _Client extends Fake implements MediaServerClient {
  _Client(this.itemsApi);
  @override
  final ItemsApi itemsApi;
}

void main() {
  late PlaybackManager manager;
  late _Items items;
  setUp(() async {
    PlatformDetection.setTvMode(true);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    final users = UserRepository();
    users.setCurrentUser(
      PrivateUser(
        id: 'viewer',
        name: 'Viewer',
        serverId: 'server',
        accessToken: 'fixture',
        lastUsed: DateTime(2026),
        canManageSubtitles: true,
      ),
    );
    GetIt.instance.registerSingleton<UserRepository>(users);
    manager = PlaybackManager();
    manager.queueService.setQueue([
      AggregatedItem(
        id: 'movie',
        serverId: 'server',
        rawData: {
          'Id': 'movie',
          'Name': 'Film',
          'Type': 'Movie',
          'MediaSources': [
            {'Id': 'source'},
          ],
        },
      ),
    ]);
    items = _Items();
  });
  tearDown(() async {
    manager.dispose();
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Future<void> search(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1145, 644));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Builder(
            builder: (context) => Tv26Button(
              label: 'Subtitles',
              autofocus: true,
              onPressed: () => TrackPicker.show(
                context,
                manager: manager,
                audio: false,
                clientFor: (_) => _Client(items),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(items.searches, greaterThan(0));
    expect(tester.takeException(), isNull);
  }

  testWidgets('remote subtitle results cancel without downloading', (
    tester,
  ) async {
    await search(tester);
    expect(find.text('English subtitles'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(items.downloads, 0);
  });
  for (final failed in [false, true]) {
    testWidgets(
      'remote subtitle provider empty/error stays dismissible ($failed)',
      (tester) async {
        items.fail = failed;
        items.empty = !failed;
        await search(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(items.downloads, 0);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<Tv26Button>()
              ?.label,
          'Subtitles',
        );
      },
    );
  }
}
