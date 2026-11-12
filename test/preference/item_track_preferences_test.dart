import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const english = <String, dynamic>{
    'Type': 'Subtitle',
    'Index': 3,
    'Language': 'eng',
    'Codec': 'PGSSUB',
  };
  Future<UserPreferences> prefs([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final store = PreferenceStore();
    await store.init();
    return UserPreferences(store);
  }

  test(
    'legacy numbers are preserved but cannot override language defaults',
    () async {
      final p = await prefs({'pref_item_subtitle_index_film': 4});
      expect(p.getItemSubtitleStreamIndex('film', streams: [english]), -2);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'pref_item_subtitle_index_film',
        ),
        4,
      );
    },
  );
  test(
    'persisted selection resolves after stream renumbering and clearing',
    () async {
      final p = await prefs();
      await p.setItemSubtitleStreamIndex('film', 3, streams: [english]);
      expect(
        p.getItemSubtitleStreamIndex(
          'film',
          streams: [
            {...english, 'Index': 4},
          ],
        ),
        4,
      );
      await p.setItemSubtitleStreamIndex('film', null);
      expect(p.getItemSubtitleStreamIndex('film', streams: [english]), -2);
      await p.setItemSubtitleStreamIndex('film', -1);
      expect(p.getItemSubtitleStreamIndex('film', streams: [english]), -1);
    },
  );
  test('saved identities are isolated between signed-in profiles', () async {
    final p = await prefs({
      'pref_last_server_id': 'server',
      'pref_last_user_id': 'first',
    });
    await p.setItemSubtitleStreamIndex('film', 3, streams: [english]);
    await p.set(UserPreferences.lastUserId, 'second');
    expect(p.getItemSubtitleStreamIndex('film', streams: [english]), -2);
    await p.set(UserPreferences.lastUserId, 'first');
    expect(p.getItemSubtitleStreamIndex('film', streams: [english]), 3);
  });
  test('new profiles inherit the server default-audio policy', () async {
    final p = await prefs({
      'pref_last_server_id': 'server',
      'pref_last_user_id': 'new',
    });
    p.initLanguagePrefs(
      UserConfiguration.fromJson({
        'PlayDefaultAudioTrack': true,
        'SubtitleLanguagePreference': 'eng',
        'SubtitleMode': 'Always',
      }),
    );
    expect(p.get(UserPreferences.preferDefaultAudioTrack), isTrue);
    await p.set(UserPreferences.preferDefaultAudioTrack, false);
    p.initLanguagePrefs(
      UserConfiguration.fromJson({'PlayDefaultAudioTrack': true}),
    );
    expect(p.get(UserPreferences.preferDefaultAudioTrack), isFalse);
  });
}
