import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _PluginSync extends Mock implements PluginSyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final people = [
    {'Id': 'lead', 'Name': 'Lead', 'Type': 'Actor', 'Role': 'Jesse'},
    {'Id': 'guest', 'Name': 'Guest', 'Type': 'GuestStar', 'Role': 'Guest'},
    {'Id': 'lead', 'Name': 'Lead', 'Type': 'Writer'},
    {'Id': 'guest', 'Name': 'Guest', 'Type': 'Director'},
  ];

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    final plugin = _PluginSync();
    when(() => plugin.seerrAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(plugin);
  });
  tearDown(() => GetIt.instance.reset());

  for (final type in ['Movie', 'BoxSet']) {
    test('$type retains cast members who also write or direct', () async {
      final client = _Client();
      final api = _ItemsApi();
      when(() => client.itemsApi).thenReturn(api);
      when(() => client.baseUrl).thenReturn('http://server');
      when(
        () => api.getItem('item', mediaSourceId: any(named: 'mediaSourceId')),
      ).thenAnswer(
        (_) async => {
          'Id': 'item',
          'Type': type,
          'Name': 'Title',
          'People': people,
        },
      );
      if (type == 'BoxSet') {
        when(
          () => api.getItems(
            parentId: 'item',
            startIndex: 0,
            limit: any(named: 'limit'),
            fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People',
          ),
        ).thenAnswer(
          (_) async => {
            'Items': [
              {'Id': 'child', 'Type': 'Movie', 'People': people},
            ],
            'TotalRecordCount': 1,
          },
        );
      }
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'item',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      addTearDown(vm.dispose);
      await vm.load();
      if (type == 'BoxSet') {
        for (var i = 0; i < 100 && vm.collectionItems.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(vm.collectionItems, hasLength(1));
      }
      expect(vm.actors.map((p) => p['Name']), ['Lead', 'Guest']);
      expect(vm.actors.map((p) => p['Role']), ['Jesse', 'Guest']);
      expect(vm.writers.single['Name'], 'Lead');
      expect(vm.directors.single['Name'], 'Guest');
    });
  }
}
