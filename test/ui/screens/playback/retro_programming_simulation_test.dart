import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_dial.dart';
import 'package:server_core/server_core.dart';

/// Run against an owner-supplied, read-only catalog export. No server writes or
/// streams are opened. Private catalog data remains outside the repository.
void main() {
  const fixture = String.fromEnvironment('RETRO_TV_LIBRARY_FIXTURE');
  for (final seed in [4, 12, 29]) {
    test(
      'seed $seed: real catalog supports a continuous, varied week without simulcasts',
      () async {
        final raw = jsonDecode(
          File(fixture).readAsStringSync(),
        ) as Map<String, dynamic>;
        final stations = RetroStation.fromJson(
          jsonDecode(
            File('assets/programming/media_categories.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        );
        final now = DateTime.utc(2026, 11, 12, 2);
        final dial = RetroTvDial(
          _Library(raw),
          'fixture',
          stations: stations,
          clock: () => now,
          random: Random(seed),
        );
        await dial.loadInitial();
        final slots = <String, (RetroChannel, RetroProgram)>{};
        final watch = Stopwatch()..start();
        for (var step = 0; step <= 7 * 48; step++) {
          final at = now.add(Duration(minutes: 30 * step));
          dial.update(at);
          for (final channel in dial.channels) {
            expect(channel.now.startsAt.isAfter(at), isFalse);
            expect(channel.now.endsAt.isAfter(at), isTrue);
            expect(channel.next.startsAt, channel.now.endsAt);
            expect(
              channel.programs.last.endsAt.isBefore(
                at.add(RetroTvDial.horizon),
              ),
              isFalse,
            );
            for (var i = 0; i < channel.programs.length; i++) {
              final p = channel.programs[i];
              expect(channel.station.matches(p.item, at: now), isTrue);
              if (i > 0) {
                expect(
                  retroTitleKey(p.item),
                  isNot(retroTitleKey(channel.programs[i - 1].item)),
                );
                expect(p.startsAt, channel.programs[i - 1].endsAt);
              }
              slots['${channel.station.name}:${p.item.id}:${p.startsAt}'] = (
                channel,
                p,
              );
            }
          }
        }
        final families = <String, List<(RetroChannel, RetroProgram)>>{};
        for (final slot in slots.values) {
          (families[retroFamilyKey(slot.$2.item)] ??= []).add(slot);
        }
        for (final entries in families.values) {
          entries.sort((a, b) => a.$2.startsAt.compareTo(b.$2.startsAt));
          for (var i = 1; i < entries.length; i++) {
            expect(
              entries[i].$2.startsAt.isBefore(entries[i - 1].$2.endsAt),
              isFalse,
              reason:
                  '${entries[i].$2.item.name} overlaps ${entries[i - 1].$1.station.label} and ${entries[i].$1.station.label}',
            );
          }
        }
        final gaps = <double>[];
        for (final entries in families.values) {
          if (entries.first.$2.item.type != 'Movie') continue;
          for (var i = 1; i < entries.length; i++) {
            gaps.add(
              entries[i].$2.startsAt
                      .difference(entries[i - 1].$2.endsAt)
                      .inMinutes /
                  60,
            );
          }
        }
        gaps.sort();
        final movies = slots.values
            .where((e) => e.$2.item.type == 'Movie')
            .map((e) => retroTitleKey(e.$2.item))
            .toSet();
        final usedEpisodes = slots.values
            .where((e) => e.$2.item.type == 'Episode')
            .map((e) => retroTitleKey(e.$2.item))
            .toSet();
        debugPrint(
          'SIMULATION ${jsonEncode({
            'seed': seed,
            'channels': dial.channels.length,
            'movies': dial.movieCount,
            'episodes': dial.episodeCount,
            'uniqueMoviesScheduled': movies.length,
            'uniqueEpisodesScheduled': usedEpisodes.length,
            'slots': slots.length,
            'movieRepeatGapHoursMin': gaps.isEmpty ? null : gaps.first,
            'movieRepeatGapHoursMedian': gaps.isEmpty ? null : gaps[gaps.length ~/ 2],
            'milliseconds': watch.elapsedMilliseconds,
            'lineup': [
              for (final c in dial.channels) {'number': c.number, 'name': c.station.label},
            ],
          })}',
        );
        expect(dial.channels.length, greaterThan(29));
        expect(
          movies.length,
          greaterThanOrEqualTo((dial.movieCount * .90).floor()),
        );
      },
      skip: fixture.isEmpty
          ? 'Supply --dart-define=RETRO_TV_LIBRARY_FIXTURE=/path/to/export.json'
          : false,
    );
  }
}

class _Library extends Fake implements ItemsApi {
  _Library(this.raw);
  final Map<String, dynamic> raw;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    final type = (args[#includeItemTypes] as List<String>).single;
    final rows =
        (raw[switch (type) {
                  'Movie' => 'movies',
                  'Series' => 'shows',
                  _ => 'episodes',
                }]
                as List)
            .cast<Map<String, dynamic>>();
    final start = args[#startIndex] as int;
    final limit = args[#limit] as int;
    return Future.value(<String, dynamic>{
      'Items': rows.skip(start).take(limit).toList(),
    });
  }
}
