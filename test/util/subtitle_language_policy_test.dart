import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations_en.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/widgets/playback/track_choices.dart';
import 'package:moonfin/util/secondary_subtitle_track_selection.dart';
import 'package:moonfin/util/subtitle_track_logic.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends PlaybackManager {
  _Manager(this.streams, {this.primary = -1, this.secondary = -1});
  final List<Map<String, dynamic>> streams;
  final int primary;
  final int secondary;
  @override
  StreamResolutionResult get currentResolution => StreamResolutionResult(
    streamUrl: 'https://example.invalid/movie',
    mediaSourceId: 'source',
    playMethod: StreamPlayMethod.directPlay,
    mediaStreams: streams,
  );
  @override
  int get subtitleStreamIndex => primary;
  @override
  int get secondarySubtitleStreamIndex => secondary;
  @override
  int get audioStreamIndex => 101;
  @override
  Future<int?> getSubtitleStreamIndexAsync() async => primary;
  @override
  bool canUseAsSecondarySubtitle(int index) => true;
}

Map<String, dynamic> sub(int index, String? language, {bool forced = false}) =>
    {
      'Type': 'Subtitle',
      'Index': index,
      'Language': language,
      'Codec': 'subrip',
      'IsForced': forced,
    };

int? resolve(
  List<Map<String, dynamic>> streams, {
  int? selected,
  int? active,
  String preferred = 'eng',
}) => computeEffectiveSubtitleIndex(
  subtitleStreams: streams,
  selectedSubtitleIndex: selected,
  activePlaybackSubtitleIndex: active,
  subtitleMode: SubtitleMode.always,
  preferredLanguage: preferred,
  fallbackLanguage: 'kor',
  preferSdh: false,
  pgsDirectPlay: true,
  assDirectPlay: true,
  preferredAudioLanguage: 'jpn',
  activeAudioLanguage: 'jpn',
);

void main() {
  test('English and Korean aliases and regional variants only', () {
    for (final language in [
      'en',
      'eng',
      'EN-us',
      'eng_GB',
      'English',
      'ko',
      'kor',
      'KO-kr',
      'kor_KR',
      'Korean',
    ]) {
      expect(
        isAllowedSubtitleStream(sub(3, language)),
        isTrue,
        reason: language,
      );
    }
    for (final language in [null, '', 'und', 'ja', 'jpn', 'fra', 'est']) {
      expect(
        isAllowedSubtitleStream(sub(3, language)),
        isFalse,
        reason: '$language',
      );
    }
  });

  test('hidden remembered selections fall back; permitted and Off survive', () {
    final streams = [
      sub(2, 'est'),
      sub(9, 'eng', forced: true),
      sub(35, 'en-US'),
      sub(71, 'kor'),
    ];
    expect(resolve(streams, selected: 2), 35);
    expect(resolve(streams, active: 2), 35);
    expect(resolve(streams, selected: 71), 71);
    expect(resolve(streams, selected: 9), 9);
    expect(resolve(streams, selected: -1), -1);
    expect(resolve(streams, preferred: 'kor'), 71);
    expect(resolve([sub(2, 'est'), sub(5, null)], selected: 2), -1);
  });

  test(
    'mixed sparse catalogue keeps raw indices and audio while filtering rows',
    () async {
      final streams = [
        for (var i = 0; i < 25; i++)
          sub(
            i * 3 + 2,
            i == 3
                ? 'eng'
                : i == 21
                ? 'kor'
                : 'est',
          ),
        {'Type': 'Audio', 'Index': 101, 'Language': 'jpn'},
        {'Type': 'Audio', 'Index': 109, 'Language': 'fra'},
      ];
      final manager = _Manager(streams, primary: 11, secondary: 65);
      addTearDown(manager.dispose);
      final l10n = AppLocalizationsEn();
      final primary = await TrackChoices.load(manager, l10n, audio: false);
      expect(primary.allStreams, same(streams));
      expect(primary.streams, hasLength(25));
      expect(primary.optionStreams.map((s) => s['Index']), [11, 65]);
      expect(primary.options, hasLength(3));
      expect(primary.selectedIndex, 1);
      expect(primary.streamIndexFor(0), -1);
      expect(primary.streamIndexFor(1), 11);
      expect(primary.streamIndexFor(2), 65);
      expect(
        primary.streamIndexFor(3),
        isNull,
      ); // first appended control/download
      final secondary = await TrackChoices.load(
        manager,
        l10n,
        audio: false,
        secondary: true,
      );
      expect(secondary.optionStreams.single['Index'], 65);
      expect(secondary.selectedIndex, 1);
      final audio = await TrackChoices.load(manager, l10n, audio: true);
      expect(audio.optionStreams.map((s) => s['Language']), ['jpn', 'fra']);
      expect(audio.streamIndexFor(1), 109);
    },
  );

  test(
    'all permitted variants stay visible and unknown-only menus show Off',
    () async {
      final manager = _Manager([
        sub(3, 'eng'),
        sub(8, 'eng', forced: true),
        {...sub(20, 'kor'), 'IsHearingImpaired': true},
        sub(40, null),
      ]);
      addTearDown(manager.dispose);
      final choices = await TrackChoices.load(
        manager,
        AppLocalizationsEn(),
        audio: false,
      );
      expect(choices.optionStreams.map((s) => s['Index']), [3, 8, 20]);
      final unknown = _Manager([sub(2, null), sub(5, 'est')]);
      addTearDown(unknown.dispose);
      for (final secondary in [false, true]) {
        final off = await TrackChoices.load(
          unknown,
          AppLocalizationsEn(),
          audio: false,
          secondary: secondary,
        );
        expect(off.options, hasLength(1));
        expect(off.selectedIndex, 0);
        expect(off.streamIndexFor(0), -1);
      }
    },
  );

  test(
    'secondary restore rejects hidden language without changing raw ordinals',
    () {
      final streams = [sub(2, 'est'), sub(20, 'eng'), sub(80, 'kor')];
      final foreign = secondarySubtitleTrackSelection(streams, 2);
      final korean = secondarySubtitleTrackSelection(streams, 80);
      expect(korean['ordinal'], 2);
      expect(
        restoreSecondarySubtitleTrack(
          foreign,
          streams,
          isCompatible: isAllowedSubtitleStream,
        ),
        -1,
      );
      expect(
        restoreSecondarySubtitleTrack(
          korean,
          streams,
          isCompatible: isAllowedSubtitleStream,
        ),
        80,
      );
    },
  );
}
