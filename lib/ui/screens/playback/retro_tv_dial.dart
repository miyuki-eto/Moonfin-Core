import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import 'retro_tv_programming.dart';
import 'retro_tv_schedule_store.dart';

export 'retro_tv_programming.dart';

class RetroProgram {
  RetroProgram(AggregatedItem item, this.startsAt)
    : endsAt = startsAt.add(item.runtime!),
      // Separate airings have separate playback identities, even for reruns.
      item = AggregatedItem(
        id: item.id,
        serverId: item.serverId,
        rawData: item.rawData,
      );
  final AggregatedItem item;
  final DateTime startsAt;
  final DateTime endsAt;
  Duration positionAt(DateTime now) => now.difference(startsAt);
}

class RetroChannel {
  RetroChannel(this.station);
  final RetroStation station;
  final _programs = ListQueue<RetroProgram>();
  int get number => station.index + 1;
  RetroProgram get now => _programs.first;
  RetroProgram get next => _programs.elementAt(1);
  List<RetroProgram> get programs => List.unmodifiable(_programs);
}

/// Coordinates one broadcast lineup over the full playable library.
/// Each station reserves a small fallback rotation. Other titles remain shared,
/// subject to global overlap checks and least-recently-aired selection.
class RetroTvDial {
  RetroTvDial(
    this._items,
    this._serverId, {
    Random? random,
    List<RetroStation>? stations,
    this.store,
    DateTime Function()? clock,
  }) : _random = random ?? Random(),
       _definitions = stations,
       _clock = clock ?? DateTime.timestamp;

  factory RetroTvDial.forClient(MediaServerClient client, String serverId) {
    final scope = (serverId, client.userId, client.itemsApi);
    final cached = _clientDials[client];
    if (cached != null && cached.$1 == scope) return cached.$2;
    final dial = RetroTvDial(
      scope.$3,
      serverId,
      store: RetroTvScheduleStore(serverId, client.userId),
    );
    _clientDials[client] = (scope, dial);
    return dial;
  }
  static final _clientDials =
      Expando<((String, String?, ItemsApi), RetroTvDial)>();
  static const horizon = Duration(hours: 24);
  static const _historyWindow = Duration(days: 7);
  static const _refreshInterval = Duration(hours: 6);
  final ItemsApi _items;
  final String _serverId;
  final Random _random;
  final List<RetroStation>? _definitions;
  final RetroTvScheduleStore? store;
  final DateTime Function() _clock;
  List<RetroStation> _stations = [];
  final _titles = <String, AggregatedItem>{};
  final _channels = <String, RetroChannel>{};
  final _pools = <String, List<AggregatedItem>>{};
  final _owners = <String, String>{};
  final _history = <RetroProgram>[];
  final _lastAired = <String, RetroProgram>{};
  DateTime? _lastRead;
  Future<void>? _reading;
  Future<void> _write = Future.value();
  String _signature = '';

  List<RetroChannel> get channels =>
      _channels.values.toList()..sort((a, b) => a.number.compareTo(b.number));
  int get movieCount => _titles.values.where((i) => i.type == 'Movie').length;
  int get episodeCount =>
      _titles.values.where((i) => i.type == 'Episode').length;

  Future<void> loadInitial() async {
    if (_lastRead != null) return;
    _stations = _definitions ?? await RetroStation.load();
    final cached = await store?.read();
    if (cached != null && _restoreCatalog(cached)) {
      _updateSignature();
      if (_restore(cached)) return;
      _titles.clear();
      _lastRead = null;
    }
    await _readCatalog();
    _updateSignature();
    final restored = cached != null && _restore(cached);
    if (!restored) _buildLineup();
    _lastRead = _clock();
    if (restored) await persist();
  }

  void _updateSignature() {
    final ids = _titles.keys.toList()..sort();
    _signature = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final id in ids) [id, _titles[id]!.runTimeTicks],
              for (final station in _stations) [station.name, station.rule],
            ]),
          ),
        )
        .toString();
  }

  bool _restoreCatalog(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['version'] != 2) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(
        data['catalogAt'] as int,
        isUtc: true,
      );
      final age = _clock().difference(at);
      if (age.isNegative || age > _historyWindow) return false;
      final catalog = (data['catalog'] as List).cast<Map<String, dynamic>>();
      if (catalog.isEmpty) return false;
      final loaded = <String, AggregatedItem>{};
      for (final raw in catalog) {
        final item = AggregatedItem(
          id: raw['Id'] as String,
          serverId: _serverId,
          rawData: raw,
        );
        if ((item.type != 'Movie' && item.type != 'Episode') ||
            (item.runtime ?? Duration.zero) < const Duration(minutes: 3)) {
          return false;
        }
        loaded[item.id] = item;
      }
      _titles.addAll(loaded);
      _lastRead = at;
      return true;
    } on FormatException catch (error) {
      debugPrint('Ignoring invalid Retro TV catalog cache: $error');
      return false;
    } on TypeError catch (error) {
      debugPrint('Ignoring invalid Retro TV catalog cache: $error');
      return false;
    }
  }

  Future<void> refill() {
    if (_lastRead == null ||
        _clock().difference(_lastRead!) < _refreshInterval) {
      return Future.value();
    }
    return _reading ??= _refresh().whenComplete(() => _reading = null);
  }

  Future<void> _refresh() async {
    await _readCatalog();
    // Keep station reservations and committed slots stable during a session.
    for (final channel in channels) {
      _pools[channel.station.name] = _candidates(channel.station);
    }
    _lastRead = _clock();
    _updateSignature();
    await persist();
  }

  Future<List<Map<String, dynamic>>> _readType(String type) async {
    final rows = <Map<String, dynamic>>[];
    // Rich cast/crew pages need the same small batches as the Windows reader.
    final size = type == 'Episode' ? 250 : 50;
    for (var offset = 0; ; offset += size) {
      final response = await _items
          .getItems(
            includeItemTypes: [type],
            recursive: true,
            collapseBoxSetItems: false,
            sortBy: 'SortName',
            startIndex: offset,
            limit: size,
            fields: type == 'Episode'
                ? 'Genres,RunTimeTicks,ProviderIds,DateCreated'
                : 'Genres,RunTimeTicks,ProviderIds,People,Overview,ProductionLocations,DateCreated,Studios,Tags',
            enableTotalRecordCount: false,
          )
          .timeout(const Duration(seconds: 20));
      final batch = (response['Items'] as List).cast<Map<String, dynamic>>();
      rows.addAll(batch);
      if (batch.length < size) return rows;
    }
  }

  Future<void> _readCatalog() async {
    final pages = await Future.wait([
      _readType('Movie'),
      _readType('Series'),
      _readType('Episode'),
    ]);
    final shows = {for (final row in pages[1]) row['Id']: row};
    final unique = <String>{};
    final loaded = <String, AggregatedItem>{};
    for (final row in [...pages[0], ...pages[2]]) {
      if (row['IsPlaceHolder'] == true ||
          row['LocationType'] == 'Virtual' ||
          row['IsFolder'] == true ||
          row['Id'] is! String) {
        continue;
      }
      final parent = shows[row['SeriesId']];
      final data = <String, dynamic>{
        ...?parent,
        ...row,
        if (parent != null && (row['Genres'] as List? ?? []).isEmpty)
          'Genres': parent['Genres'] ?? [],
        // Series identity/ratings/country describe the programme. Episode
        // numbers, title and actual runtime always come from the episode.
        if (parent != null) 'CommunityRating': parent['CommunityRating'],
      };
      final item = AggregatedItem(
        id: row['Id'] as String,
        serverId: _serverId,
        rawData: _programmingMetadata(data),
      );
      if ((item.runtime ?? Duration.zero) < const Duration(minutes: 3)) {
        continue;
      }
      if (item.type != 'Movie' && item.type != 'Episode') continue;
      if (unique.add(retroTitleKey(item))) loaded[item.id] = item;
    }
    if (loaded.isEmpty) throw StateError('No playable movies or episodes');
    // Retain scheduled identities if the server temporarily omits an item;
    // new scheduling only sees the refreshed eligible pools.
    _titles.addAll(loaded);
  }

  List<AggregatedItem> _candidates(RetroStation station) => _titles.values
      .where((item) => station.matches(item, at: _clock()))
      .toList();

  void _buildLineup() {
    final entries = <(RetroStation, List<AggregatedItem>)>[];
    final seenPools = <String>{};
    final directors = <(RetroStation, List<AggregatedItem>)>[];
    for (final station in _stations) {
      final pool = _candidates(station);
      final identities = pool.map(retroFamilyKey).toSet().toList()..sort();
      if (station.television) {
        final grouped = _groupSeries(pool);
        if (!grouped.values.any((episodes) => episodes.length >= 2)) continue;
      } else {
        final hours =
            pool.fold<int>(0, (sum, i) => sum + i.runtime!.inMinutes) / 60;
        if (station == RetroStation.cinema) {
          if (pool.length < 2) continue;
        } else if (pool.length < (station.director ? 4 : 6) || hours < 8) {
          continue;
        }
      }
      if (station.director) {
        directors.add((station, pool));
      } else if (seenPools.add(
        '${station.television}:${identities.join(',')}',
      )) {
        entries.add((station, pool));
      }
    }
    // Four eligible director spotlights, seeded by the Brisbane broadcast day.
    // Restored lineups retain their identities and committed programming.
    if (directors.isNotEmpty) {
      final day = _clock().toUtc().add(const Duration(hours: 10));
      final first =
          DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
          86400000;
      for (var i = 0; i < min(4, directors.length); i++) {
        entries.add(directors[(first + i) % directors.length]);
      }
    }
    int priority(RetroStation station) =>
        station == RetroStation.cinema || station == RetroStation.tvReplay
        ? 0
        : station.rule.containsKey('titles') ||
              station.director ||
              const {
                'crime',
                'scifi',
                'action',
                'comedy',
                'drama',
              }.contains(station.name)
        ? 1
        : 2;
    entries.sort((a, b) {
      final p = priority(a.$1).compareTo(priority(b.$1));
      return p != 0 ? p : a.$2.length.compareTo(b.$2.length);
    });
    final movieHours =
        _titles.values
            .where((i) => i.type == 'Movie')
            .fold<int>(0, (sum, i) => sum + i.runtime!.inMinutes) /
        60;
    final movieLimit = max(1, (movieHours / 16).floor());
    var movieChannels = 0;
    // A bipartite reservation keeps every admitted channel viable, while most
    // of the library remains available to all matching channels.
    final slots = <(String, List<String>)>[];
    final assignments = <String, int>{};
    for (final (station, pool) in entries) {
      if (!station.television && movieChannels >= movieLimit) continue;
      final families = station.television
          ? _groupSeries(pool).entries
                .where((e) => e.value.length >= 2)
                .map((e) => e.key)
                .toList()
          : pool.map(retroFamilyKey).toList();
      families.shuffle(_random);
      final previous = Map<String, int>.of(assignments);
      final start = slots.length;
      var fits = true;
      for (var i = 0; i < (station.television ? 1 : 2); i++) {
        slots.add((station.name, families));
        if (!_reserve(slots.length - 1, slots, assignments, {})) {
          fits = false;
          break;
        }
      }
      if (!fits) {
        slots.removeRange(start, slots.length);
        assignments
          ..clear()
          ..addAll(previous);
        continue;
      }
      _channels[station.name] = RetroChannel(station);
      _pools[station.name] = pool;
      if (!station.television) movieChannels++;
    }
    for (final entry in assignments.entries) {
      _owners[entry.key] = slots[entry.value].$1;
    }
  }

  bool _reserve(
    int slot,
    List<(String, List<String>)> slots,
    Map<String, int> assignments,
    Set<String> visited,
  ) {
    for (final key in slots[slot].$2) {
      if (!visited.add(key)) continue;
      final owner = assignments[key];
      if (owner == null || _reserve(owner, slots, assignments, visited)) {
        assignments[key] = slot;
        return true;
      }
    }
    return false;
  }

  Map<String, List<AggregatedItem>> _groupSeries(List<AggregatedItem> pool) {
    final groups = <String, List<AggregatedItem>>{};
    for (final item in pool) {
      (groups[retroSeriesKey(item)] ??= []).add(item);
    }
    for (final episodes in groups.values) {
      episodes.sort((a, b) {
        final season = (a.parentIndexNumber ?? 0).compareTo(
          b.parentIndexNumber ?? 0,
        );
        return season != 0
            ? season
            : (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
      });
    }
    return groups;
  }

  void update(DateTime now) {
    var changed = false;
    _history.removeWhere(
      (p) => p.endsAt.isBefore(now.subtract(_historyWindow)),
    );
    for (final channel in channels) {
      while (channel._programs.isNotEmpty && !channel.now.endsAt.isAfter(now)) {
        final expired = channel._programs.removeFirst();
        _history.add(expired);
        _lastAired[channel.station.name] = expired;
        changed = true;
      }
    }
    final occupied = <String, List<RetroProgram>>{};
    final recent = <String, RetroProgram>{};
    for (final program in [
      ..._history,
      for (final c in channels) ...c._programs,
    ]) {
      final key = retroFamilyKey(program.item);
      (occupied[key] ??= []).add(program);
      final previous = recent[key];
      if (previous == null || program.endsAt.isAfter(previous.endsAt)) {
        recent[key] = program;
      }
    }
    // Fill the earliest open slot across the whole lineup, not a whole day on
    // one station before the others get a chance to choose.
    while (true) {
      final pending =
          channels
              .where(
                (c) =>
                    c._programs.length < 2 ||
                    c._programs.last.endsAt.isBefore(now.add(horizon)),
              )
              .toList()
            ..sort(
              (a, b) => (a._programs.lastOrNull?.endsAt ?? now).compareTo(
                b._programs.lastOrNull?.endsAt ?? now,
              ),
            );
      if (pending.isEmpty) break;
      final channel = pending.first;
      final last =
          channel._programs.lastOrNull ?? _lastAired[channel.station.name];
      final start = last?.endsAt ?? now;
      final program = _choose(
        channel,
        last,
        start,
        occupied,
        recent,
        inProgress: last == null,
      );
      if (program == null) {
        // Reservations make this impossible for an intact catalog. Surface a
        // violated invariant instead of silently simulcasting or repeating.
        throw StateError(
          'No non-repeating programme for ${channel.station.label}',
        );
      }
      if (!program.endsAt.isAfter(now)) {
        _history.add(program);
        _lastAired[channel.station.name] = program;
      } else {
        channel._programs.add(program);
      }
      final family = retroFamilyKey(program.item);
      (occupied[family] ??= []).add(program);
      recent[family] = program;
      changed = true;
    }
    if (changed) unawaited(persist());
  }

  RetroProgram? _choose(
    RetroChannel channel,
    RetroProgram? last,
    DateTime start,
    Map<String, List<RetroProgram>> occupied,
    Map<String, RetroProgram> recent, {
    required bool inProgress,
  }) {
    final pool = _pools[channel.station.name]!;
    final groups = channel.station.television
        ? _groupSeries(pool)
        : {
            for (final item in pool) retroTitleKey(item): [item],
          };
    final keys = groups.keys.toList()..shuffle(_random);
    keys.sort(
      (a, b) => (recent[a]?.endsAt ?? DateTime.utc(1970)).compareTo(
        recent[b]?.endsAt ?? DateTime.utc(1970),
      ),
    );
    for (final key in keys) {
      if (_owners[key] != null && _owners[key] != channel.station.name) {
        continue;
      }
      final choices = groups[key]!;
      final previous = recent[key]?.item;
      var cursor = previous == null
          ? _random.nextInt(choices.length)
          : (choices.indexWhere(
                      (i) => retroTitleKey(i) == retroTitleKey(previous),
                    ) +
                    1) %
                choices.length;
      for (var i = 0; i < choices.length; i++) {
        final item = choices[(cursor + i) % choices.length];
        if (last != null && retroTitleKey(last.item) == retroTitleKey(item)) {
          continue;
        }
        final position = inProgress
            ? item.runtime! * (.20 + _random.nextDouble() * .45)
            : Duration.zero;
        final program = RetroProgram(item, start.subtract(position));
        if ((occupied[key] ?? const []).any(
          (p) =>
              p.startsAt.isBefore(program.endsAt) &&
              p.endsAt.isAfter(program.startsAt),
        )) {
          continue;
        }
        return program;
      }
    }
    return null;
  }

  Future<void> persist() {
    if (store == null || _channels.isEmpty) return Future.value();
    final value = jsonEncode({
      'version': 2,
      'catalogAt':
          _lastRead?.millisecondsSinceEpoch ?? _clock().millisecondsSinceEpoch,
      'catalog': [for (final item in _titles.values) item.rawData],
      'signature': _signature,
      'savedAt': _clock().millisecondsSinceEpoch,
      'owners': _owners,
      'lastAired': {
        for (final entry in _lastAired.entries) entry.key: _slot(entry.value),
      },
      'channels': {
        for (final c in channels)
          c.station.name: [for (final p in c._programs) _slot(p)],
      },
      'history': [for (final p in _history) _slot(p)],
    });
    return _write = _write.then((_) => store!.write(value)).catchError((
      Object error,
    ) {
      debugPrint('Retro TV schedule cache write failed: $error');
    });
  }

  Map<String, dynamic> _slot(RetroProgram program) => {
    'id': program.item.id,
    'start': program.startsAt.microsecondsSinceEpoch,
  };

  bool _restore(String value) {
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['version'] != 2 ||
          data['signature'] != _signature ||
          _clock().difference(
                DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int),
              ) >
              _historyWindow) {
        return false;
      }
      final definitions = {for (final s in _stations) s.name: s};
      final restored = <String, RetroChannel>{};
      RetroProgram program(dynamic raw) {
        final slot = raw as Map<String, dynamic>;
        final item = _titles[slot['id']];
        if (item == null) throw const FormatException('Scheduled item missing');
        return RetroProgram(
          item,
          DateTime.fromMicrosecondsSinceEpoch(
            slot['start'] as int,
            isUtc: true,
          ),
        );
      }

      for (final entry in (data['channels'] as Map<String, dynamic>).entries) {
        final station = definitions[entry.key];
        if (station == null) return false;
        final channel = RetroChannel(station);
        channel._programs.addAll((entry.value as List).map(program));
        if (channel._programs.length < 2 ||
            !channel._programs.every(
              (p) => station.matches(p.item, at: _clock()),
            )) {
          return false;
        }
        restored[entry.key] = channel;
      }
      final owners = (data['owners'] as Map).cast<String, String>();
      if (restored.isEmpty || !owners.values.every(restored.containsKey)) {
        return false;
      }
      final history = (data['history'] as List).map(program).toList();
      final lastAired = (data['lastAired'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, program(value)),
      );
      final pools = {
        for (final c in restored.values) c.station.name: _candidates(c.station),
      };
      for (final c in restored.values) {
        final owned = owners.entries
            .where((entry) => entry.value == c.station.name)
            .map((entry) => entry.key)
            .toSet();
        if (owned.length < (c.station.television ? 1 : 2) ||
            !owned.every(
              (key) =>
                  pools[c.station.name]!.any((i) => retroFamilyKey(i) == key),
            )) {
          return false;
        }
        for (var i = 1; i < c._programs.length; i++) {
          final before = c._programs.elementAt(i - 1);
          final after = c._programs.elementAt(i);
          if (before.endsAt != after.startsAt ||
              retroTitleKey(before.item) == retroTitleKey(after.item)) {
            return false;
          }
        }
      }
      _channels.addAll(restored);
      _pools.addAll(pools);
      _owners.addAll(owners);
      _history.addAll(history);
      _lastAired.addAll(lastAired);
      return true;
    } on FormatException catch (error) {
      debugPrint('Ignoring invalid Retro TV schedule cache: $error');
      return false;
    } on TypeError catch (error) {
      debugPrint('Ignoring invalid Retro TV schedule cache: $error');
      return false;
    }
  }
}

Map<String, dynamic> _programmingMetadata(Map<String, dynamic> data) => {
  for (final key in const [
    'Id',
    'Name',
    'Type',
    'Genres',
    'ProviderIds',
    'ProductionYear',
    'RunTimeTicks',
    'SeriesId',
    'SeriesName',
    'ParentIndexNumber',
    'IndexNumber',
    'CommunityRating',
    'ProductionLocations',
    'Overview',
    'DateCreated',
    'ImageTags',
    'BackdropImageTags',
    'ParentBackdropItemId',
    'ParentBackdropImageTags',
    'ParentLogoItemId',
    'ParentLogoImageTag',
    'Studios',
  ])
    if (data.containsKey(key)) key: data[key],
  'People': [
    for (final person in (data['People'] as List? ?? const []))
      if ((person as Map)['Type'] == 'Director') person,
  ],
};
