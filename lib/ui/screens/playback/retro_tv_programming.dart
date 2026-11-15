import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../data/models/aggregated_item.dart';

/// Authored category rules shared with Media's Windows home rotation.
/// TV uses the complete matching library, not the home row's displayed slice.
class RetroStation {
  const RetroStation(this.name, this.label, this.index, {this.rule = const {}});

  final String name;
  final String label;
  final int index;
  final Map<String, dynamic> rule;

  static const cinema = RetroStation('cinema', 'Cinema', 0);
  static const tvReplay = RetroStation(
    'tvReplay',
    'TV Replay',
    1,
    rule: {'kind': 'tv'},
  );
  static const values = [cinema, tvReplay];

  bool get television => rule['kind'] == 'tv';
  bool get director => rule.containsKey('director');

  bool matches(AggregatedItem item, {DateTime? at}) {
    if (item.type != (television ? 'Episode' : 'Movie')) return false;
    final today = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 10));
    List<String> strings(String key) =>
        (rule[key] as List? ?? const []).map((v) => v.toString()).toList();
    final genres = item.genres.map((g) => g.toLowerCase()).toSet();
    final any = strings('genres_any').map((g) => g.toLowerCase());
    final all = strings('genres_all').map((g) => g.toLowerCase());
    if (any.isNotEmpty && !any.any(genres.contains)) return false;
    if (!all.every(genres.contains)) return false;
    final year = item.productionYear;
    if (rule['year_min'] case final num min) {
      if (year == null || year < min) return false;
    }
    if (rule['year_max'] case final num max) {
      if (year == null || year > max) return false;
    }
    if (rule['last_years'] case final num years) {
      if (year == null || year < today.year - years) return false;
    }
    if (rule['rating_min'] case final num rating) {
      if ((item.communityRating ?? 0) < rating) return false;
    }
    final minutes = item.runtime?.inSeconds.toDouble();
    if (rule['minutes_min'] case final num min) {
      if (minutes == null || minutes < min * 60) return false;
    }
    if (rule['minutes_max'] case final num max) {
      if (minutes == null || minutes > max * 60) return false;
    }
    final countries = strings('countries').map((c) => c.toLowerCase()).toSet();
    if (countries.isNotEmpty &&
        !(item.rawData['ProductionLocations'] as List? ?? const []).any(
          (c) => countries.contains(c.toString().toLowerCase()),
        )) {
      return false;
    }
    if (rule['recent_days'] case final num days) {
      final added = DateTime.tryParse(
        item.rawData['DateCreated']?.toString() ?? '',
      );
      if (added == null ||
          today
                  .difference(added.toUtc().add(const Duration(hours: 10)))
                  .inDays >
              days) {
        return false;
      }
    }
    final collections = strings('tmdb_collection_ids');
    if (collections.isNotEmpty &&
        !collections.contains(item.providerIds['TmdbCollection'])) {
      return false;
    }
    if (rule['director'] case final String name) {
      if (!item.people.any(
        (p) =>
            p['Type'] == 'Director' &&
            programmingName(p['Name']?.toString() ?? '') ==
                programmingName(name),
      )) {
        return false;
      }
    }
    final ids = strings('tmdb_ids');
    if (ids.isNotEmpty && !ids.contains(item.tmdbId)) return false;
    final titles = strings('titles');
    final keywords = strings('keywords');
    if (titles.isNotEmpty || keywords.isNotEmpty) {
      final titleMatch = titles.any(
        (t) => programmingName(t) == programmingName(item.name),
      );
      final overview = (item.overview ?? '').toLowerCase();
      final keywordMatch = keywords.any(
        (word) =>
            RegExp(r'(?<!\w)' + RegExp.escape(word.toLowerCase()) + r'(?!\w)')
                .hasMatch(overview),
      );
      if (!titleMatch && !keywordMatch) return false;
    }
    return true;
  }

  static Future<List<RetroStation>> load() async => fromJson(
    jsonDecode(
      await rootBundle.loadString('assets/programming/media_categories.json'),
    ) as Map<String, dynamic>,
  );

  static List<RetroStation> fromJson(Map<String, dynamic> source) {
    final themes = (source['themes'] as List).cast<Map<String, dynamic>>();
    final directors = (source['directors'] as List).cast<String>();
    final numbers =
        (source['channel_numbers'] as Map?)?.cast<String, int>() ?? {};
    int index(String name, int fallback) => (numbers[name] ?? fallback + 1) - 1;
    return [
      ...values,
      for (var i = 0; i < themes.length; i++)
        if (!(themes[i]['code'] as String).startsWith('franchise:'))
          RetroStation(
            themes[i]['code'] as String,
            themes[i]['name'] as String,
            index(themes[i]['code'] as String, i + 2),
            rule: themes[i],
          ),
      // Small franchises make one deep spotlight pool, rather than
      // fourteen channels looping two or three films each.
      RetroStation(
        'franchises',
        'Franchise Spotlight',
        index('franchises', themes.length + 2),
        rule: {
          'tmdb_collection_ids': [
            for (final theme in themes)
              ...(theme['tmdb_collection_ids'] as List? ?? const []),
          ],
        },
      ),
      for (var decade = 1970; decade <= 2020; decade += 10)
        RetroStation(
          'decade:$decade',
          '${decade}s Cinema',
          index('decade:$decade', themes.length + 3 + (decade - 1970) ~/ 10),
          rule: {'year_min': decade, 'year_max': decade + 9},
        ),
      for (var i = 0; i < directors.length; i++)
        RetroStation(
          'director:${directors[i]}',
          directors[i],
          index('director:${directors[i]}', themes.length + 9 + i),
          rule: {'director': directors[i]},
        ),
    ];
  }
}

String programmingName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

String retroTitleKey(AggregatedItem item) => item.type == 'Episode'
    ? '${retroSeriesKey(item)}:${item.parentIndexNumber ?? 0}:${item.indexNumber ?? item.id}'
    : item.tmdbId != null
    ? 'movie:tmdb:${item.tmdbId}'
    : item.imdbId != null
    ? 'movie:imdb:${item.imdbId}'
    : 'movie:${programmingName(item.name)}:${item.productionYear ?? item.id}';

String retroSeriesKey(AggregatedItem item) =>
    'series:${item.seriesId ?? (item.seriesName?.isNotEmpty == true ? programmingName(item.seriesName!) : item.id)}';

String retroFamilyKey(AggregatedItem item) =>
    item.type == 'Episode' ? retroSeriesKey(item) : retroTitleKey(item);
