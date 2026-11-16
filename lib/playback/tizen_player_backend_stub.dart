import 'package:flutter/widgets.dart';
import 'package:playback_core/playback_core.dart';

import '../preference/user_preferences.dart';

/// Keeps the native FFI player out of browser builds.
abstract class TizenPlayerBackend extends PlayerBackend
    implements SubtitleLoadingBackend {
  factory TizenPlayerBackend(UserPreferences prefs) =>
      throw UnsupportedError('The Tizen player requires a native TV build');

  Widget buildView({bool ready = true, BoxFit fit = BoxFit.contain});

  @override
  Stream<Map<String, dynamic>> get errorStream;
}
