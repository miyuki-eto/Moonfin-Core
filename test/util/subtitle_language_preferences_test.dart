import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/series_track_preference.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/detail_track_highlight.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Manager extends PlaybackManager {
  String? rememberedLanguage;
  @override
  String? get lastExplicitSubtitleLanguage => rememberedLanguage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UserPreferences prefs;
  late _Manager manager;
  final subtitles = <Map<String, dynamic>>[
    {'Index': 2, 'Language': 'est', 'Title': 'Estonian'},
    {'Index': 19, 'Language': 'eng', 'Title': 'English'},
    {'Index': 70, 'Language': 'kor', 'Title': 'Korean'},
  ];
  int? highlight({int? selected}) => highlightedSubtitleIndex(
    subtitleStreams: subtitles,
    audioStreams: const [],
    seriesId: 'series',
    selectedIndex: selected,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    manager = _Manager();
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
    await prefs.set(UserPreferences.defaultSubtitleLanguage, 'eng');
    await prefs.set(UserPreferences.fallbackSubtitleLanguage, 'kor');
    await prefs.set(UserPreferences.subtitleMode, SubtitleMode.always);
  });
  tearDown(() async {
    manager.dispose();
    await GetIt.instance.reset();
  });

  test('hidden saved series hint cannot turn global Off back on', () async {
    const saved = SeriesTrackPreference(
      language: 'est',
      title: 'Estonian',
      relativeIndex: 0,
    );
    await prefs.setSeriesSubtitlePreference('series', saved);
    await prefs.set(UserPreferences.subtitleMode, SubtitleMode.none);
    expect(highlight(), -1);
    expect(prefs.getSeriesSubtitlePreference('series').language, 'est');
  });

  test('hidden remembered hint does not override the English default', () {
    manager.rememberedLanguage = 'est';
    expect(highlight(), 19);
    expect(highlight(selected: 2), 19);
    expect(manager.rememberedLanguage, 'est');
  });

  test('permitted hint and explicit selections remain authoritative', () {
    manager.rememberedLanguage = 'kor';
    expect(highlight(), 70);
    expect(highlight(selected: 19), 19);
    expect(highlight(selected: -1), -1);
  });
}
