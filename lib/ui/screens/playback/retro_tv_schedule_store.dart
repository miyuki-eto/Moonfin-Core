import 'package:shared_preferences/shared_preferences.dart';

/// Local schedule facts only: item IDs and broadcast times, never stream URLs.
class RetroTvScheduleStore {
  RetroTvScheduleStore(String server, String? user)
    : _key =
          'retro-tv-schedule-v2:${Uri.encodeComponent(server)}:${user ?? ''}';
  final String _key;

  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(_key, value)) {
      throw StateError('Could not save the Retro TV schedule');
    }
  }
}
