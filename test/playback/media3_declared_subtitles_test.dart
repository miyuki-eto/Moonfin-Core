import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _control = MethodChannel('moonfin/media3_video_control');
const _events = MethodChannel('moonfin/media3_video_events');

// A sidecar added after the source opened re-prepares the player, and an
// episode with several subtitle files showed that as a run of restarts. Sent
// with the source, they are all in the first prepare.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Media3PlayerBackend backend;
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, (call) async {
          calls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, (_) async => null);
    backend = Media3PlayerBackend(UserPreferences(store));
  });

  tearDown(() {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, null);
  });

  Map<dynamic, dynamic> sourceArguments() =>
      calls.singleWhere((call) => call.method == 'setSource').arguments as Map;

  test('unreported full-screen playback uses the main player slot', () async {
    await backend.play(
      {'url': 'http://server/video.mkv', 'preview': true},
      startPosition: const Duration(minutes: 5),
    );

    expect(sourceArguments()['preview'], isFalse);
    expect(sourceArguments()['startPositionMs'], 300000);
  });

  test('mid-film Retro timing uses the same clock and resets on a new programme', () async {
    const position = Duration(minutes: 70);
    await backend.play({
      'url': 'http://server/batman.mkv',
      'preview': true,
      'subtitleDelaySessionId': 10,
    }, startPosition: position);
    expect(sourceArguments()['preview'], isFalse);
    expect(sourceArguments()['startPositionMs'], position.inMilliseconds);
    for (final delay in [-0.5, 0.5, 0.0]) {
      await backend.setSubtitleDelay(delay);
      final call = calls.lastWhere((c) => c.method == 'setSubtitleDelay');
      expect(call.arguments['delayMs'], (delay * 1000).round());
    }
    await backend.setSubtitleDelay(0.5);
    calls.clear();
    await backend.play({
      'url': 'http://server/batman.mkv',
      'preview': true,
      'subtitleDelaySessionId': 11,
    }, startPosition: position + const Duration(minutes: 1));
    expect(sourceArguments()['subtitleDelayMs'], 0);
    expect(sourceArguments()['startPositionMs'], 4260000);
  });

  test('inline trailers use the native preview slot', () async {
    await backend.play('http://server/trailer.mkv', inlinePreview: true);

    expect(sourceArguments()['preview'], isTrue);
  });

  test('the sidecars a source came with go out with the source', () async {
    const sidecars = [
      {
        'url': 'http://server/1.srt',
        'codec': 'srt',
        'language': 'hin',
        'title': 'Hindi',
      },
      {
        'url': 'http://server/2.srt',
        'codec': 'srt',
        'language': 'eng',
        'title': 'English',
      },
    ];

    await backend.play(<String, dynamic>{
      'url': 'http://server/video.mkv',
      'mediaType': 'video',
      'externalSubtitles': sidecars,
    });

    expect(sourceArguments()['externalSubtitles'], sidecars);
  });

  test('a source with no sidecars declares none', () async {
    await backend.play(<String, dynamic>{
      'url': 'http://server/video.mkv',
      'mediaType': 'video',
    });

    expect(sourceArguments()['externalSubtitles'], isEmpty);
  });
}
