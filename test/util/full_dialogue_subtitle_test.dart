import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/data/models/series_track_preference.dart';
import 'package:moonfin/util/subtitle_track_logic.dart';

void main() {
  const partial = <String, dynamic>{
    'Type': 'Subtitle', 'Index': 3, 'Language': 'eng',
    'Title': 'Signs & Songs', 'Codec': 'ass', 'IsDefault': true,
  };
  const full = <String, dynamic>{
    'Type': 'Subtitle', 'Index': 4, 'Language': 'eng',
    'Title': 'English SDH', 'Codec': 'subrip',
    'IsExternal': true, 'IsHearingImpaired': true,
  };
  int? select({SubtitleMode mode = SubtitleMode.always, int? explicit}) =>
      computeEffectiveSubtitleIndex(
        subtitleStreams: [partial, full], selectedSubtitleIndex: explicit,
        activePlaybackSubtitleIndex: null, subtitleMode: mode,
        preferredLanguage: 'eng', fallbackLanguage: '', preferSdh: false,
        pgsDirectPlay: true, assDirectPlay: true,
        preferredAudioLanguage: 'auto', activeAudioLanguage: 'jpn',
      );

  test('full English SDH beats internal signs and songs', () {
    expect(select(), 4);
  });
  test('forced mode and explicit partial choice remain available', () {
    expect(select(mode: SubtitleMode.forced), 3);
    expect(select(explicit: 3), 3);
    expect(select(explicit: -1), -1);
  });
  test('remembered signs choice survives a changed title', () {
    expect(matchSeriesTrackIndex(
      streams: [full, {...partial, 'Title': 'English Signs & Songs'}],
      pref: const SeriesTrackPreference(language: 'eng', title: 'Signs & Songs'),
    ), 3);
  });
  test('a full track mentioning signs is not classified as partial', () {
    expect(isForcedSubtitleStream({'Title': 'Full dialogue + signs'}), isFalse);
    expect(isForcedSubtitleStream({'Title': 'English (Non-forced)'}), isFalse);
    expect(isForcedSubtitleStream({'Title': 'Signs & Songs'}), isTrue);
    expect(isForcedSubtitleStream({'Title': 'English signs only'}), isTrue);
    expect(isForcedSubtitleStream({'Title': 'Songs from the Second Floor'}), isFalse);
  });
}
