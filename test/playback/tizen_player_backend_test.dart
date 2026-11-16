import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/tizen_player_backend.dart';
import 'package:moonfin/ui/widgets/pgs_subtitle_view.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_videohole/video_player.dart' as vp;
import 'package:video_player_videohole/video_player_platform_interface.dart'
    as native;

class _Player extends native.VideoPlayerPlatform {
  final events = <int, StreamController<native.VideoEvent>>{};
  final sources = <native.DataSource>[];
  final played = <int>[];
  final positionsAtPlay = <Duration>[];
  final selected = <int>[];
  final disposed = <int>[];
  final positions = <int, Duration>{};
  final seeks = <({int id, Duration position})>[];
  int peakPlayers = 0;
  bool holdPrepare = false;
  Completer<void>? heldSeek;
  final rectangles = <Rect>[];

  @override
  Future<void> init() async {}
  @override
  Future<int?> create(native.DataSource source) async {
    sources.add(source);
    final id = sources.length;
    events[id] = StreamController<native.VideoEvent>();
    positions[id] = Duration.zero;
    if (events.length > peakPlayers) peakPlayers = events.length;
    return id;
  }

  @override
  Stream<native.VideoEvent> videoEventsFor(int id) {
    if (!holdPrepare) scheduleMicrotask(() => emitPrepared(id));
    return events[id]!.stream;
  }

  void emitPrepared(int id) => events[id]!.add(
    native.VideoEvent(
      eventType: native.VideoEventType.initialized,
      duration: native.DurationRange(
        Duration.zero,
        const Duration(minutes: 90),
      ),
      size: const Size(1920, 1080),
    ),
  );
  @override
  Future<void> dispose(int id) async {
    disposed.add(id);
    await events.remove(id)?.close();
  }

  @override
  Future<void> play(int id) async {
    played.add(id);
    positionsAtPlay.add(positions[id]!);
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> seekTo(int id, Duration position) async {
    seeks.add((id: id, position: position));
    await heldSeek?.future;
    positions[id] = position;
  }

  @override
  Future<Duration> getPosition(int id) async => positions[id]!;
  @override
  Future<native.DurationRange> getDuration(int id) async =>
      native.DurationRange(Duration.zero, const Duration(minutes: 90));
  @override
  Future<List<vp.AudioTrack>> getAudioTracks(int id) async => [
    vp.AudioTrack(trackId: 7, language: 'eng', channel: 2, bitrate: 128000),
    vp.AudioTrack(trackId: 41, language: 'fra', channel: 2, bitrate: 128000),
  ];
  @override
  Future<List<vp.TextTrack>> getTextTracks(int id) async => [
    vp.TextTrack(trackId: 19, language: 'eng'),
  ];
  @override
  Future<bool> setTrackSelection(int id, vp.Track track) async {
    selected.add(track.trackId);
    return true;
  }

  @override
  Future<void> setDisplayGeometry(
    int id,
    int x,
    int y,
    int width,
    int height,
  ) async {
    rectangles.add(
      Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
    );
  }

  @override
  Future<bool> setDisplayRotate(
    int id,
    native.DisplayRotation rotation,
  ) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Player player;
  late TizenPlayerBackend backend;
  bool nativeWidgetTest = false;
  setUp(() async {
    nativeWidgetTest = false;
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    player = _Player();
    native.VideoPlayerPlatform.instance = player;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('tizen/device_info_plus'),
          (_) async => {
            'platformVersion': '6.5',
            'freeDiskSize': 0,
            'totalDiskSize': 0,
            'physicalRamSize': 1024,
            'availableRamSize': 512,
            'screenWidth': 1920,
            'screenHeight': 1080,
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('tizen/internal/window'),
          (_) async => 0,
        );
    backend = TizenPlayerBackend(UserPreferences(store));
  });
  tearDown(() async {
    if (nativeWidgetTest) return; // The widget test releases IO in runAsync.
    await backend.stop();
    backend.dispose();
    await Future<void>.value();
  });

  test(
    'preview preserves the requested start and waits for explicit resume',
    () async {
      await backend.play({
        'url': 'http://server/movie.mp4',
        'autoPlay': false,
      }, startPosition: const Duration(minutes: 12));
      expect(player.seeks, [(id: 1, position: const Duration(minutes: 12))]);
      expect(backend.position, const Duration(minutes: 12));
      expect(player.played, isEmpty);
      expect(backend.playWhenReady, isFalse);
      await backend.resume();
      expect(player.played, [1]);
      expect(backend.playWhenReady, isTrue);
      await backend.pause();
      expect(backend.playWhenReady, isFalse);
    },
  );

  test('a transcoded source seeks before autoplay', () async {
    await backend.play(
      'http://server/master.m3u8',
      startPosition: const Duration(minutes: 59),
    );
    expect(player.seeks, [(id: 1, position: const Duration(minutes: 59))]);
    expect(player.played, [1]);
    expect(player.positionsAtPlay, [const Duration(minutes: 59)]);
    expect(backend.position, const Duration(minutes: 59));
  });

  test(
    'audio ordinals select native IDs rather than container indices',
    () async {
      await backend.play({
        'url': 'http://server/movie.mkv',
        'audioTrackOrdinal': 2,
      });
      expect(player.selected, [41]);
      await backend.setAudioTrack(1);
      expect(player.selected, [41, 7]);
      await expectLater(backend.setAudioTrack(3), throwsStateError);
    },
  );

  test(
    'late preparation cannot play a superseded source or overlap decoders',
    () async {
      player.holdPrepare = true;
      final first = backend.play('http://server/one.mp4');
      while (player.sources.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final second = backend.play('http://server/two.mp4');
      player.holdPrepare = false;
      player.emitPrepared(1);
      await first;
      await second;
      expect(player.played, [2]);
      expect(player.disposed, [1]);
      expect(player.peakPlayers, 1);
    },
  );

  test('stop cancels a prepare that never becomes ready', () async {
    player.holdPrepare = true;
    final opening = backend.play('http://server/one.mp4');
    while (player.sources.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final stopped = backend.stop();
    await Future.wait([opening, stopped]).timeout(const Duration(seconds: 1));
    expect(player.played, isEmpty);
    expect(player.events, isEmpty);
    expect(backend.isPlaying, isFalse);
  });

  test('a pending startup seek can be abandoned for another channel', () async {
    final seek = player.heldSeek = Completer<void>();
    final opening = backend.play(
      'http://server/slow.m3u8',
      startPosition: const Duration(minutes: 20),
    );
    while (player.seeks.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final stopped = backend.stop();
    await Future.wait([opening, stopped]).timeout(const Duration(seconds: 1));
    player.heldSeek = null;
    await backend.play('http://server/next.mp4');
    seek.complete();
    await Future<void>.value();
    expect(player.played, [2]);
    expect(player.disposed, [1]);
    expect(player.peakPlayers, 1);
  });

  test(
    'subtitle ordinal maps to native ID and off suppresses captions',
    () async {
      await backend.play('http://server/movie.mkv');
      await backend.setSubtitleTrack(1);
      expect(player.selected, [19]);
      expect(backend.activeSubtitleTrackIndex, 1);
      await backend.disableSubtitleTrack();
      expect(backend.activeSubtitleTrackIndex, -1);
    },
  );

  test(
    'native errors are emitted once and a later source can recover',
    () async {
      final errors = <Map<String, dynamic>>[];
      final sub = backend.errorStream.listen(errors.add);
      await backend.play('http://server/one.mp4');
      player.events[1]!.addError(
        PlatformException(code: 'decode', message: 'decoder rejected source'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      await backend.play('http://server/two.mp4');
      expect(player.played.last, 2);
      await sub.cancel();
    },
  );

  testWidgets(
    'UTF8 sidecar captions, delay, off and native picture fit work together',
    (tester) async {
      nativeWidgetTest = true;
      addTearDown(
        () => tester.runAsync(() async {
          await backend.stop();
          backend.dispose();
        }),
      );
      await tester.runAsync(() async {
        await backend.play({
          'url': 'http://server/movie.mkv',
          'autoPlay': false,
        });
        await http.runWithClient(
          () => backend.setSubtitleTrack(
            1,
            isExternalSubtitle: true,
            externalSubtitleUrl: 'http://server/sub.srt',
            subtitleCodec: 'srt',
          ),
          () => MockClient(
            (_) async => http.Response.bytes(
              utf8.encode(
                '\uFEFF1\n00:00:05,000 --> 00:00:06,000\n<i>Résumé &amp; café</i>\n\n',
              ),
              200,
            ),
          ),
        );
        await backend.seekTo(const Duration(seconds: 5));
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: backend.buildView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Résumé & café'), findsOneWidget);
      expect(tester.getSize(find.byType(vp.VideoPlayer)), const Size(800, 450));
      expect(
        tester.getTopLeft(find.byType(vp.VideoPlayer)),
        const Offset(0, 75),
      );
      await backend.setSubtitleDelay(2);
      await tester.pump();
      expect(find.text('Résumé & café'), findsNothing);
      await tester.runAsync(() => backend.seekTo(const Duration(seconds: 7)));
      await tester.pump();
      expect(find.text('Résumé & café'), findsOneWidget);
      await backend.disableSubtitleTrack();
      await tester.pump();
      expect(find.text('Résumé & café'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'a late subtitle request cannot turn subtitles back on after Off',
    () async {
      await backend.play('http://server/movie.mkv');
      final response = Completer<http.Response>();
      final loading = http.runWithClient(
        () => backend.setSubtitleTrack(
          1,
          isExternalSubtitle: true,
          externalSubtitleUrl: 'http://server/sub.vtt',
          subtitleCodec: 'vtt',
        ),
        () => MockClient((_) => response.future),
      );
      while (!backend.isSubtitleLoading) {
        await Future<void>.delayed(Duration.zero);
      }
      await backend.disableSubtitleTrack();
      response.complete(
        http.Response(
          'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nLate cue\n',
          200,
        ),
      );
      await loading;
      expect(backend.activeSubtitleTrackIndex, -1);
      expect(backend.isSubtitleLoading, isFalse);
    },
  );

  testWidgets('native subtitle events do not repeat cached cues after a seek', (
    tester,
  ) async {
    nativeWidgetTest = true;
    addTearDown(
      () => tester.runAsync(() async {
        await backend.stop();
        backend.dispose();
      }),
    );
    await tester.runAsync(() async {
      await backend.play({'url': 'http://server/movie.mkv', 'autoPlay': false});
      await backend.setSubtitleTrack(1);
      await backend.seekTo(const Duration(seconds: 5));
      player.events[1]!.add(
        native.VideoEvent(
          eventType: native.VideoEventType.subtitleUpdate,
          duration: native.DurationRange(
            Duration.zero,
            const Duration(seconds: 3),
          ),
          text: 'Native caption',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: backend.buildView(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Native caption'), findsOneWidget);
    await tester.runAsync(() => backend.seekTo(const Duration(seconds: 6)));
    await tester.pump();
    expect(find.text('Native caption'), findsNothing);
    await tester.runAsync(() async {
      player.events[1]!.add(
        native.VideoEvent(
          eventType: native.VideoEventType.subtitleUpdate,
          duration: native.DurationRange(
            Duration.zero,
            const Duration(seconds: 2),
          ),
          text: 'New cue',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('New cue'), findsOneWidget);
    await backend.disableSubtitleTrack();
    await tester.pump();
    expect(find.text('New cue'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'PGS loading runs after video starts and Off cancels a pending file',
    () async {
      await backend.play('http://server/movie.mkv');
      expect(player.played, [1]);
      final response = Completer<http.Response>();
      final loading = http.runWithClient(
        () => backend.setSubtitleTrack(
          1,
          isBitmapSubtitle: true,
          subtitleCodec: 'pgssub',
          externalSubtitleUrl: 'http://server/sub.sup',
        ),
        () => MockClient((_) => response.future),
      );
      while (!backend.isSubtitleLoading) {
        await Future<void>.delayed(Duration.zero);
      }
      await loading.timeout(const Duration(seconds: 1));
      expect(player.disposed, isEmpty);
      expect(player.sources, hasLength(1));
      await backend.disableSubtitleTrack();
      response.complete(
        http.Response.bytes(
          File('test/fixtures/pgs/libpgs.sup').readAsBytesSync(),
          200,
        ),
      );
      await loading;
      expect(backend.activeSubtitleTrackIndex, -1);
      expect(backend.isSubtitleLoading, isFalse);
      expect(player.sources, hasLength(1));
    },
  );

  test('a failed PGS download does not restart or dispose the video', () async {
    await backend.play('http://server/movie.mkv');
    await http.runWithClient(
      () => backend.setSubtitleTrack(
        1,
        isBitmapSubtitle: true,
        subtitleCodec: 'pgs',
        externalSubtitleUrl: 'http://server/sub.sup',
      ),
      () => MockClient((_) async => http.Response('Unavailable', 503)),
    );
    while (backend.isSubtitleLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(backend.isSubtitleLoading, isFalse);
    expect(player.disposed, isEmpty);
    expect(player.sources, hasLength(1));
  });
  testWidgets(
    'PGS paints through the native adapter, respects delay and reports a failed track',
    (tester) async {
      nativeWidgetTest = true;
      addTearDown(
        () => tester.runAsync(() async {
          await backend.stop();
          backend.dispose();
        }),
      );
      await tester.runAsync(() async {
        await backend.play('http://server/movie.mkv');
        await http.runWithClient(
          () => backend.setSubtitleTrack(
            1,
            isBitmapSubtitle: true,
            subtitleCodec: 'pgssub',
            externalSubtitleUrl: 'http://server/sub.sup',
          ),
          () => MockClient(
            (_) async => http.Response.bytes(
              File('test/fixtures/pgs/libpgs.sup').readAsBytesSync(),
              200,
            ),
          ),
        );
        await backend.seekTo(const Duration(milliseconds: 1500));
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: backend.buildView(),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.byType(RawImage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(PgsSubtitleView), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(player.selected, isEmpty);
      expect(player.sources, hasLength(1));
      await backend.setSubtitleDelay(2);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      await tester.runAsync(
        () => http.runWithClient(
          () => backend.setSubtitleTrack(
            1,
            isBitmapSubtitle: true,
            subtitleCodec: 'pgssub',
            externalSubtitleUrl: 'http://server/bad.sup',
          ),
          () => MockClient((_) async => http.Response.bytes([0, 0], 200)),
        ),
      );
      await tester.runAsync(() async {
        while (backend.isSubtitleLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pump();
      expect(
        find.textContaining('Subtitles could not be loaded'),
        findsOneWidget,
      );
      expect(player.sources, hasLength(1));
      expect(player.disposed, isEmpty);
      await backend.disableSubtitleTrack();
      await tester.pump();
      expect(
        find.textContaining('Subtitles could not be loaded'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
