import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/favorites_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ratings extends Mock implements MdbListRepository {}

void main() {
  for (final style in [FavoritesViewStyle.home, FavoritesViewStyle.library]) {
    test(
      'unfavorite removes the item and keeps $style pagination aligned',
      () async {
        await GetIt.instance.reset();
        userDataSync.reset();
        SharedPreferences.setMockInitialValues({});
        final store = PreferenceStore();
        await store.init();
        final prefs = UserPreferences(store);
        await prefs.set(UserPreferences.favoritesViewStyle, style);
        GetIt.instance.registerSingleton<UserPreferences>(prefs);
        final ids = ['a', 'b', 'c'];
        final offsets = <int>[];
        final client = JellyfinMediaServerClient(
          baseUrl: 'http://favorites.test',
          deviceInfo: const DeviceInfo(
            id: 'test',
            name: 'test',
            appName: 'test',
            appVersion: 'test',
          ),
          interceptors: [
            InterceptorsWrapper(
              onRequest: (request, handler) {
                if (request.method == 'DELETE' &&
                    request.uri.path.endsWith('/a')) {
                  ids.remove('a');
                  handler.resolve(
                    Response(requestOptions: request, statusCode: 204),
                  );
                  return;
                }
                final types = request.queryParameters['IncludeItemTypes'];
                if (request.method != 'GET' ||
                    !request.uri.path.endsWith('/Items')) {
                  handler.reject(
                    DioException(
                      requestOptions: request,
                      error: 'Unexpected endpoint',
                    ),
                  );
                  return;
                }
                final movies =
                    types == null ||
                    types.toString().split(',').contains('Movie');
                final offset = int.parse(
                  '${request.queryParameters['StartIndex'] ?? 0}',
                );
                if (movies) {
                  offsets.add(offset);
                }
                final page = movies
                    ? ids.skip(offset).take(2).toList()
                    : <String>[];
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: {
                      'Items': [
                        for (final id in page)
                          {
                            'Id': id, 'Name': id, 'Type': 'Movie',
                            // A favorite endpoint may omit the flag; an unrelated watched
                            // patch must not remove such an item.
                            'UserData': id == 'b'
                                ? <String, dynamic>{}
                                : {'IsFavorite': true},
                          },
                      ],
                      'TotalRecordCount': movies ? ids.length : 0,
                    },
                  ),
                );
              },
            ),
          ],
        )..userId = 'viewer';
        final vm = FavoritesViewModel(
          client: client,
          prefs: prefs,
          mdbListRepository: _Ratings(),
        );
        addTearDown(() async {
          vm.dispose();
          userDataSync.reset();
          await GetIt.instance.reset();
        });
        await vm.load();
        expect(vm.state, FavoritesState.ready);
        List<String> visible() =>
            (style == FavoritesViewStyle.home
                    ? vm.rowItems[FavoriteTypeFilter.movie] ?? []
                    : vm.gridItems)
                .map((item) => item.id)
                .toList();
        expect(visible(), ['a', 'b']);
        userDataSync.publish('b', {'Played': true});
        expect(visible(), ['a', 'b']);
        await ItemMutationRepository(client)
            .setFavorite('a', isFavorite: false);
        expect(visible(), ['b']);
        if (style == FavoritesViewStyle.home) {
          expect(vm.rowTotalCount(FavoriteTypeFilter.movie), 2);
          await vm.loadMoreForType(FavoriteTypeFilter.movie);
        } else {
          expect(vm.gridTotalCount, 2);
          await vm.loadMoreGrid();
        }
        expect(offsets, [0, 1]);
        expect(visible(), ['b', 'c']);
        userDataSync.publishAll({
          'b': {'IsFavorite': false},
          'c': {'IsFavorite': false},
        });
        expect(visible(), isEmpty);
        expect(vm.totalCount, 0);
        if (style == FavoritesViewStyle.home) {
          expect(vm.rowItems, isEmpty);
        }

        // Clearing the loaded page must not hide favorites on later pages.
        ids
          ..clear()
          ..addAll(['a', 'b', 'c']);
        userDataSync.reset();
        await vm.load();
        ids.removeWhere((id) => id == 'a' || id == 'b');
        final refilled = Completer<void>();
        vm.addListener(() {
          if (!refilled.isCompleted &&
              visible().length == 1 &&
              visible().single == 'c') {
            refilled.complete();
          }
        });
        userDataSync.publishAll({
          'a': {'IsFavorite': false},
          'b': {'IsFavorite': false},
        });
        await refilled.future.timeout(const Duration(seconds: 2));
        expect(visible(), ['c']);
      },
    );
  }

  test(
    'leaving Favorites during its first request permits a late response',
    () async {
      await GetIt.instance.reset();
      userDataSync.reset();
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(
        UserPreferences.favoritesViewStyle,
        FavoritesViewStyle.library,
      );
      GetIt.instance.registerSingleton<UserPreferences>(prefs);
      final requested = Completer<void>();
      final reply = Completer<void>();
      final client = JellyfinMediaServerClient(
        baseUrl: 'http://favorites.test',
        deviceInfo: const DeviceInfo(
          id: 'test',
          name: 'test',
          appName: 'test',
          appVersion: 'test',
        ),
        interceptors: [
          InterceptorsWrapper(
            onRequest: (request, handler) async {
              requested.complete();
              await reply.future;
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {'Items': [], 'TotalRecordCount': 0},
                ),
              );
            },
          ),
        ],
      )..userId = 'viewer';
      final vm = FavoritesViewModel(
        client: client,
        prefs: prefs,
        mdbListRepository: _Ratings(),
      );
      final loading = vm.load();
      await requested.future;
      vm.dispose();
      reply.complete();
      await expectLater(loading, completes);
      userDataSync.reset();
      await GetIt.instance.reset();
    },
  );
}
