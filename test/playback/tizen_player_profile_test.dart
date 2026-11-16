import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/tizen_player_profile.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UserPreferences prefs;
  setUp(() async {
    // flutter-tizen reports Linux; Flutter's test default is Android, whose
    // bundled FFmpeg decoder intentionally overrides hardware TrueHD probes.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'BU8000 direct play excludes unsupported lossless audio and Dolby Vision',
    () {
      final profile = buildTizenPlayerProfile(prefs);
      final video = (profile['DirectPlayProfiles'] as List)
          .whereType<Map>()
          .firstWhere((p) => p['Type'] == 'Video');
      expect(video['VideoCodec'], contains('hevc'));
      final audio = (video['AudioCodec'] as String).split(',');
      expect(audio, containsAll(['ac3', 'eac3']));
      expect(audio, isNot(contains('truehd')));
      expect(audio, isNot(contains('dts')));
      expect(audio, isNot(contains('dca')));
      final codecs = jsonEncode(profile['CodecProfiles']);
      expect(codecs, contains('VideoProfile'));
      expect(codecs, isNot(contains('high 10')));
    },
  );

  test(
    'PGS loads as a file; ASS and other bitmap formats still require burn-in',
    () {
      final entries =
          (buildTizenPlayerProfile(prefs)['SubtitleProfiles'] as List)
              .whereType<Map>();
      for (final format in ['ass', 'ssa']) {
        expect(
          entries.where((e) => e['Format'] == format).map((e) => e['Method']),
          ['Encode'],
        );
      }
      expect(
        entries.where((e) => e['Method'] == 'External').map((e) => e['Format']),
        unorderedEquals(['srt', 'subrip', 'vtt', 'webvtt', 'pgs', 'pgssub']),
      );
      for (final format in ['pgs', 'pgssub']) {
        expect(
          entries.where((e) => e['Format'] == format && e['Method'] == 'Embed'),
          isEmpty,
        );
      }
    },
  );
}
