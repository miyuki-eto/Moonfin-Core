import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_dial.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_schedule_store.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 2);
  test(
    'broadcast slots remain continuous across boundaries and an absence',
    () async {
      final dial = RetroTvDial(
        _Library(movies: [for (var i = 0; i < 12; i++) movie('m$i')]),
        'server',
        stations: RetroStation.values,
        random: Random(4),
        clock: () => now,
      );
      await dial.loadInitial();
      dial.update(now);
      final channel = dial.channels.single;
      final current = channel.now;
      final next = channel.next;
      expect(current.startsAt.isBefore(now), isTrue);
      dial.update(now.add(const Duration(seconds: 5)));
      expect(channel.now, same(current));
      expect(channel.next, same(next));
      dial.update(current.endsAt);
      expect(channel.now, same(next));
      for (final at in [
        now.add(const Duration(days: 2)),
        now.add(const Duration(days: 7)),
      ]) {
        dial.update(at);
        expect(channel.now.startsAt.isAfter(at), isFalse);
        expect(channel.now.endsAt.isAfter(at), isTrue);
        checkLineup(dial);
      }
    },
  );

  test('all catalog pages load beyond the previous 512 item cap', () async {
    final library = _Library(
      movies: [for (var i = 0; i < 601; i++) movie('m$i')],
      shows: [show('s')],
      episodes: [for (var i = 0; i < 601; i++) episode('e$i', 's', i)],
    );
    final dial = RetroTvDial(
      library,
      'server',
      stations: RetroStation.values,
      clock: () => now,
    );
    await dial.loadInitial();
    expect(dial.movieCount, 601);
    expect(dial.episodeCount, 601);
    expect(library.requests.where((r) => r.$1 == 'Movie').map((r) => r.$2), [
      for (var offset = 0; offset <= 600; offset += 50) offset,
    ]);
    expect(library.requests.where((r) => r.$1 == 'Episode').map((r) => r.$2), [
      0,
      250,
      500,
    ]);
    dial.update(now);
    expect(dial.channels.length, 2);
  });

  test(
    'overlapping themes cannot simulcast movies or repeat them consecutively',
    () async {
      final stations = [
        RetroStation.cinema,
        const RetroStation(
          'crime',
          'Crime',
          2,
          rule: {
            'genres_any': ['Crime'],
          },
        ),
        const RetroStation(
          'thriller',
          'Thriller',
          3,
          rule: {
            'genres_any': ['Thriller'],
          },
        ),
        const RetroStation(
          'tension',
          'Tension',
          4,
          rule: {
            'genres_any': ['Crime', 'Thriller'],
          },
        ),
      ];
      final dial = RetroTvDial(
        _Library(
          movies: [
            for (var i = 0; i < 64; i++)
              movie(
                'm$i',
                genres: [if (i % 2 == 0) 'Crime', if (i % 3 == 0) 'Thriller'],
              ),
          ],
        ),
        'server',
        stations: stations,
        random: Random(5),
        clock: () => now,
      );
      await dial.loadInitial();
      final all = <String, (RetroChannel, RetroProgram)>{};
      for (var h = 0; h < 7 * 24; h++) {
        dial.update(now.add(Duration(hours: h)));
        checkLineup(dial);
        for (final c in dial.channels) {
          for (final p in c.programs) {
            all['${c.number}:${p.item.id}:${p.startsAt}'] = (c, p);
          }
        }
      }
      expect(dial.channels.length, 4);
      checkOverlaps(all.values.toList());
      expect(all.values.map((p) => p.$2.item.id).toSet().length, 64);
    },
  );

  test('small genre pools are omitted instead of looping one film', () async {
    final dial = RetroTvDial(
      _Library(
        movies: [
          for (var i = 0; i < 12; i++)
            movie('m$i', genres: i == 0 ? ['Horror'] : []),
        ],
      ),
      'server',
      stations: [
        ...RetroStation.values,
        const RetroStation(
          'horror',
          'Horror',
          2,
          rule: {
            'genres_any': ['Horror'],
          },
        ),
      ],
      clock: () => now,
    );
    await dial.loadInitial();
    dial.update(now);
    expect(dial.channels.map((c) => c.station.name), ['cinema']);
    checkLineup(dial);
    final single = RetroTvDial(
      _Library(movies: [movie('only')]),
      'server',
      stations: RetroStation.values,
    );
    await single.loadInitial();
    single.update(now);
    expect(single.channels, isEmpty);
  });

  test(
    'alternate copies share one canonical movie or episode identity',
    () async {
      final a = movie('copy-a')..['ProviderIds'] = {'Tmdb': '42'};
      final b = movie('copy-b')..['ProviderIds'] = {'Tmdb': '42'};
      final e = episode('episode-copy', 'show', 1);
      final dial = RetroTvDial(
        _Library(
          movies: [a, b, movie('other')],
          shows: [show('show')],
          episodes: [episode('e1', 'show', 1), e, episode('e2', 'show', 2)],
        ),
        'server',
        stations: RetroStation.values,
        clock: () => now,
      );
      await dial.loadInitial();
      dial.update(now);
      expect(dial.movieCount, 2);
      expect(dial.episodeCount, 2);
      checkLineup(dial);
    },
  );

  test(
    'TV selects series fairly and advances each series in episode order',
    () async {
      final dial = RetroTvDial(
        _Library(
          shows: [show('long'), show('short')],
          episodes: [
            for (var i = 1; i <= 100; i++) episode('long-$i', 'long', i),
            for (var i = 1; i <= 10; i++) episode('short-$i', 'short', i),
          ],
        ),
        'server',
        stations: [RetroStation.tvReplay],
        random: Random(8),
        clock: () => now,
      );
      await dial.loadInitial();
      dial.update(now);
      final counts = <String, int>{};
      final last = <String, int>{};
      for (final p in dial.channels.single.programs) {
        final series = p.item.seriesId!;
        counts[series] = (counts[series] ?? 0) + 1;
        if (last[series] case final int previous) {
          expect(
            p.item.indexNumber,
            previous % (series == 'long' ? 100 : 10) + 1,
          );
        }
        last[series] = p.item.indexNumber!;
        expect(p.item.genres, ['Drama']);
      }
      expect((counts['long']! - counts['short']!).abs(), lessThanOrEqualTo(1));
    },
  );

  test('different episodes of one series cannot occupy different channels together', () async {
    final dial = RetroTvDial(
      _Library(
        shows: [
          for (var i = 0; i < 4; i++)
            show('s$i', genres: [if (i < 3) 'Drama', if (i > 0) 'Comedy']),
        ],
        episodes: [
          for (var s = 0; s < 4; s++)
            for (var e = 1; e <= 10; e++) episode('$s-$e', 's$s', e),
        ],
      ),
      'server',
      stations: [
        RetroStation.tvReplay,
        const RetroStation(
          'drama',
          'TV Drama',
          2,
          rule: {
            'kind': 'tv',
            'genres_any': ['Drama'],
          },
        ),
        const RetroStation(
          'comedy',
          'TV Comedy',
          3,
          rule: {
            'kind': 'tv',
            'genres_any': ['Comedy'],
          },
        ),
      ],
      random: Random(4),
      clock: () => now,
    );
    await dial.loadInitial();
    dial.update(now);
    expect(dial.channels.length, 3);
    checkLineup(dial);
    checkOverlaps([
      for (final c in dial.channels)
        for (final p in c.programs) (c, p),
    ]);
  });

  test(
    'schedule persistence retains current/next slots and account scope',
    () async {
      final store = _Store();
      final library = _Library(
        movies: [for (var i = 0; i < 20; i++) movie('m$i')],
      );
      final first = RetroTvDial(
        library,
        'server',
        stations: RetroStation.values,
        store: store,
        random: Random(1),
        clock: () => now,
      );
      await first.loadInitial();
      first.update(now);
      await first.persist();
      final airing = first.channels.single.now;
      final next = first.channels.single.next;
      final restored = RetroTvDial(
        library,
        'server',
        stations: RetroStation.values,
        store: store,
        random: Random(99),
        clock: () => now.add(const Duration(minutes: 5)),
      );
      final requestsBeforeRestore = library.requests.length;
      await restored.loadInitial();
      expect(library.requests.length, requestsBeforeRestore);
      restored.update(now.add(const Duration(minutes: 5)));
      expect(restored.channels.single.now.item.id, airing.item.id);
      expect(restored.channels.single.now.startsAt, airing.startsAt);
      expect(restored.channels.single.next.item.id, next.item.id);
      expect(restored.channels.single.next.startsAt, next.startsAt);
      final decoded = jsonDecode(store.value!) as Map;
      expect(decoded.toString(), isNot(contains('stream')));
      expect(decoded.toString(), isNot(contains('UserData')));
      store.value = 'broken json';
      final fresh = RetroTvDial(
        library,
        'server',
        stations: RetroStation.values,
        store: store,
        clock: () => now,
      );
      await fresh.loadInitial();
      fresh.update(now);
      checkLineup(fresh);
    },
  );

  test(
    'a failed catalog read is retryable and never commits a partial library',
    () async {
      final library = _Library(
        movies: [for (var i = 0; i < 12; i++) movie('m$i')],
      )..fail = true;
      final dial = RetroTvDial(
        library,
        'server',
        stations: RetroStation.values,
        clock: () => now,
      );
      await expectLater(dial.loadInitial(), throwsStateError);
      expect(dial.movieCount, 0);
      library.fail = false;
      await dial.loadInitial();
      dial.update(now);
      checkLineup(dial);
    },
  );

  test('schedule storage isolates servers and users', () async {
    SharedPreferences.setMockInitialValues({});
    final a = RetroTvScheduleStore('server-a', 'user-a');
    await a.write('schedule-a');
    expect(await a.read(), 'schedule-a');
    expect(await RetroTvScheduleStore('server-a', 'user-b').read(), isNull);
    expect(await RetroTvScheduleStore('server-b', 'user-a').read(), isNull);
  });

  test('imported category channel numbers are unique', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final stations = await RetroStation.load();
    expect(stations.map((s) => s.name).toSet().length, stations.length);
    expect(stations.map((s) => s.index).toSet().length, stations.length);
    expect(stations.any((s) => s.label == 'Mind-Bending'), isTrue);
    expect(stations.any((s) => s.label == 'BFI technothrillers'), isTrue);
  });

  test('rule combinations preserve authored meaning and use actual episode runtime', () {
    const station = RetroStation(
      'test',
      'Test',
      3,
      rule: {
        'genres_all': ['Action', 'Thriller'],
        'year_min': 1990,
        'year_max': 1999,
        'minutes_max': 120,
      },
    );
    AggregatedItem item(Map<String, dynamic> raw) =>
        AggregatedItem(id: raw['Id'], serverId: 's', rawData: raw);
    expect(
      station.matches(
        item(movie('a', genres: ['Action', 'Thriller'], year: 1992)),
      ),
      isTrue,
    );
    expect(
      station.matches(item(movie('b', genres: ['Action'], year: 1992))),
      isFalse,
    );
    const country = RetroStation(
      'kr',
      'Korea',
      4,
      rule: {
        'countries': ['KR'],
      },
    );
    expect(
      country.matches(item(movie('kr')..['ProductionLocations'] = ['KR'])),
      isTrue,
    );
    const authored = RetroStation(
      'mind',
      'Mind',
      5,
      rule: {
        'titles': ['Donnie Darko'],
        'keywords': ['time travel'],
      },
    );
    expect(
      authored.matches(item(movie('dd')..['Name'] = 'Donnie Darko')),
      isTrue,
    );
    expect(
      authored.matches(
        item(movie('other')..['Overview'] = 'A tale about time travel.'),
      ),
      isTrue,
    );
    expect(
      authored.matches(item(movie('no')..['Overview'] = 'A timetraveller.')),
      isFalse,
    );
  });
}

void checkLineup(RetroTvDial dial) {
  for (final c in dial.channels) {
    expect(c.programs.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < c.programs.length; i++) {
      expect(c.programs[i].startsAt, c.programs[i - 1].endsAt);
      expect(
        retroTitleKey(c.programs[i].item),
        isNot(retroTitleKey(c.programs[i - 1].item)),
      );
    }
  }
}

void checkOverlaps(List<(RetroChannel, RetroProgram)> slots) {
  final groups = <String, List<RetroProgram>>{};
  for (final s in slots) {
    (groups[retroFamilyKey(s.$2.item)] ??= []).add(s.$2);
  }
  for (final group in groups.values) {
    group.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    for (var i = 1; i < group.length; i++) {
      expect(
        group[i].startsAt.isBefore(group[i - 1].endsAt),
        isFalse,
        reason: group[i].item.name,
      );
    }
  }
}

Map<String, dynamic> movie(
  String id, {
  List<String> genres = const [],
  int year = 1992,
}) => {
  'Id': id,
  'Name': id,
  'Type': 'Movie',
  'Genres': genres,
  'ProductionYear': year,
  'RunTimeTicks': 120 * 60 * 10000000,
};
Map<String, dynamic> show(String id, {List<String> genres = const ['Drama']}) =>
    {
      'Id': id,
      'Name': id,
      'Type': 'Series',
      'Genres': genres,
      'CommunityRating': 8.5,
    };
Map<String, dynamic> episode(String id, String series, int n) => {
  'Id': id,
  'Name': id,
  'Type': 'Episode',
  'SeriesId': series,
  'SeriesName': series,
  'ParentIndexNumber': 1,
  'IndexNumber': n,
  'RunTimeTicks': 30 * 60 * 10000000,
};

class _Library extends Fake implements ItemsApi {
  _Library({
    this.movies = const [],
    this.shows = const [],
    this.episodes = const [],
  });
  final List<Map<String, dynamic>> movies, shows, episodes;
  final requests = <(String, int)>[];
  bool fail = false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final a = invocation.namedArguments;
    final type = (a[#includeItemTypes] as List<String>).single;
    final start = a[#startIndex] as int;
    requests.add((type, start));
    if (fail) {
      return Future<Map<String, dynamic>>.error(
        StateError('Catalog unavailable'),
      );
    }
    final rows = switch (type) {
      'Movie' => movies,
      'Series' => shows,
      _ => episodes,
    };
    return Future.value(<String, dynamic>{
      'Items': rows.skip(start).take(a[#limit] as int).toList(),
    });
  }
}

class _Store extends RetroTvScheduleStore {
  _Store() : super('test', 'test');
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}
