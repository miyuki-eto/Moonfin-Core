import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

class _TestBackend extends Fake implements PlayerBackend {
  final _errors = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void>? playGate;
  final List<String> playedUrls = <String>[];
  final List<Duration> startPositions = <Duration>[];
  int stopCalls = 0;
  bool playing = false;
  Duration currentPosition = Duration.zero;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration =>
      playing ? const Duration(minutes: 30) : Duration.zero;

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get isPlaying => playing;

  @override
  double get playbackSpeed => 1.0;

  @override
  bool get isBuffering => false;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<Map<String, dynamic>>? get errorStream => _errors.stream;

  void emitError(Map<String, dynamic> event) => _errors.add(event);

  @override
  bool get supportsRuntimeTrackSelection => false;

  @override
  bool get canRenderBitmapSubtitles => false;

  @override
  bool get requiresStartupMediaReadyCheck => false;

  @override
  bool get nativelyHandlesStartPosition => true;

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => <String, dynamic>{};

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) async {
    playedUrls.add((mediaItem as Map<String, dynamic>)['url'] as String);
    startPositions.add(startPosition);
    currentPosition = startPosition;
    playing = true;
    // Holds the first play open so a test can land an error while the manager
    // is still waiting for media. Later plays run straight through.
    final gate = playGate;
    if (gate != null) {
      playGate = null;
      await gate.future;
    }
  }

  @override
  Future<void> waitForTracksReady() async {}

  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  @override
  Future<void> disableSubtitleTrack() async {}

  Future<void> setRepeatMode(RepeatMode mode) async {}

  @override
  void dispose() => _errors.close();
}

class _PreloadingBackend extends _TestBackend
    implements PreviewStreamPreloader {
  final preloaded = <(String, Duration)>[];
  final discarded = <String>[];

  @override
  void preloadPreviewSource(
    String url, {
    String? container,
    required Duration startPosition,
  }) => preloaded.add((url, startPosition));

  bool parkEnabled = false;
  final parked = <String>[];

  @override
  bool parkPreviewSource(String url) {
    if (!parkEnabled) return false;
    parked.add(url);
    return true;
  }

  @override
  bool hasPreviewFrame(String url, Duration position) => parked.contains(url);

  @override
  void discardPreviewSource(String url) => discarded.add(url);
}

class _TestResolver extends MediaStreamResolver {
  int calls = 0;
  final List<String?> requestedMediaSourceIds = <String?>[];
  final List<int?> requestedStartTicks = <int?>[];
  final List<bool> requestedDirectPlay = <bool>[];
  final List<int?> requestedSubtitleIndices = <int?>[];
  StreamPlayMethod playMethod = StreamPlayMethod.directStream;
  StreamPlayMethod Function(Object item)? playMethodFor;
  Future<void> Function(Object item)? waitForResolution;
  bool isLocalMedia = false;
  List<Map<String, dynamic>> mediaStreams = const [];
  int? defaultSubtitleIndex;

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    final call = ++calls;
    requestedMediaSourceIds.add(mediaSourceId);
    requestedStartTicks.add(startTimeTicks);
    requestedDirectPlay.add(enableDirectPlay);
    requestedSubtitleIndices.add(subtitleStreamIndex);
    await waitForResolution?.call(mediaItem as Object);
    final type = (mediaItem as Map<String, dynamic>)['Type'];
    final isLive = type == 'TvChannel' || type == 'LiveTvChannel';
    return StreamResolutionResult(
      streamUrl: 'https://example.test/session-$call',
      mediaSourceId: 'source-$call',
      liveStreamId: isLive ? 'live-$call' : null,
      playSessionId: 'session-$call',
      playMethod: playMethodFor?.call(mediaItem as Object) ?? playMethod,
      isLocalMedia: isLocalMedia,
      mediaStreams: mediaStreams,
      selectedSubtitleStreamIndex: subtitleStreamIndex ?? defaultSubtitleIndex,
    );
  }
}

class _ProgressRequest {
  _ProgressRequest(this.index, this.sessionId, this.events);

  final int index;
  final String? sessionId;
  final List<String> events;
  final Completer<void> completer = Completer<void>();

  Future<void> get future => completer.future.then((_) {
    events.add('progress:$sessionId:$index');
  });
}

class _TestService implements PlayerService {
  _TestService({this.stallProgress = false});

  final bool stallProgress;
  final List<String> events = <String>[];
  final List<int?> startPositions = <int?>[];
  final List<_ProgressRequest> progressRequests = <_ProgressRequest>[];
  final reportedVolumes = <(int?, bool?)>[];
  final List<StreamResolutionResult> stoppedResolutions =
      <StreamResolutionResult>[];
  final List<StreamResolutionResult> transcodingStops =
      <StreamResolutionResult>[];

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    events.add('start:${resolution.playSessionId}');
    startPositions.add(positionTicks);
  }

  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
  }) {
    reportedVolumes.add((volumeLevel, isMuted));
    if (!stallProgress) {
      events.add('progress:${resolution.playSessionId}:immediate');
      return Future<void>.value();
    }
    final request = _ProgressRequest(
      progressRequests.length,
      resolution.playSessionId,
      events,
    );
    progressRequests.add(request);
    return request.future;
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
  }) async {
    events.add('stop:${resolution.playSessionId}');
    stoppedResolutions.add(resolution);
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    transcodingStops.add(resolution);
  }

  @override
  void dispose() {}
}

PlaybackManager _manager(
  _TestBackend backend,
  _TestResolver resolver,
  _TestService service,
) => PlaybackManager()
  ..setBackend(backend)
  ..setResolver(resolver)
  ..setPlayerService(service);

void main() {
  for (final allowSubtitles in [false, true]) {
    test('preview bitmap subtitles opt-in: $allowSubtitles', () async {
      final backend = _TestBackend();
      final resolver = _TestResolver()
        ..mediaStreams = const [
          {'Type': 'Video', 'Index': 0, 'Codec': 'h264'},
          {'Type': 'Audio', 'Index': 1, 'Language': 'eng'},
          {'Type': 'Subtitle', 'Index': 2, 'Language': 'eng',
           'Codec': 'PGSSUB', 'DeliveryMethod': 'Encode'},
        ]
        ..defaultSubtitleIndex = 2;
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      addTearDown(manager.dispose);
      manager.subtitleTrackSelector = (_, _, _, _, _) => 2;
      await manager.playItems([
        {'Id': 'bitmap', 'Type': 'Movie'},
      ], preview: true, allowPreviewSubtitleTranscoding: allowSubtitles);
      expect(manager.subtitleStreamIndex, allowSubtitles ? 2 : -1);
      expect(service.events, isEmpty);
      await manager.stop();
    });
  }

  testWidgets(
    'only one adjacent preview buffers and both resolutions are reusable',
    (tester) async {
      final backend = _PreloadingBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      addTearDown(manager.dispose);
      final current = {'Id': 'current', 'Type': 'Movie'};
      final next = {'Id': 'next', 'Type': 'Movie'};
      final previous = {'Id': 'previous', 'Type': 'Movie'};
      const offset = Duration(minutes: 7);
      await manager.playItems([current], startPosition: offset, preview: true);
      manager.preparePreviewNeighbors([(next, offset), (previous, offset)]);
      await tester.pump();
      expect(resolver.calls, 3);
      expect(backend.preloaded, [('https://example.test/session-2', offset)]);

      await manager.playItems([previous], startPosition: offset, preview: true);
      expect(resolver.calls, 3);
      expect(backend.playedUrls.last, 'https://example.test/session-3');
      expect(service.transcodingStops.map((r) => r.playSessionId), [
        'session-2',
        'session-1',
      ]);
      expect(service.events, isEmpty);

      manager.preparePreviewNeighbors([(current, offset)]);
      await tester.pump();
      await manager.playItems([current], startPosition: offset, preview: true);
      expect(resolver.calls, 4);
      expect(backend.playedUrls.last, backend.preloaded.last.$1);
      expect(service.events, isEmpty);
      await manager.stop();
      expect(service.events, isEmpty);
    },
  );

  testWidgets('lookahead can buffer a direct file beside a warm encoder', (
    tester,
  ) async {
    final backend = _PreloadingBackend();
    final service = _TestService();
    final current = {'Id': 'current', 'Type': 'Movie'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    final file = {'Id': 'file', 'Type': 'Episode'};
    final transcode = {'Id': 'transcode', 'Type': 'Movie'};
    final resolver = _TestResolver()
      ..playMethodFor = (item) => identical(item, file)
          ? StreamPlayMethod.directPlay
          : StreamPlayMethod.transcode;
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    const offset = Duration(minutes: 7);
    await manager.playItems([current], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors(
      [(next, offset)],
      lookahead: (file, offset),
    );
    await tester.pump();
    expect(backend.preloaded.map((entry) => entry.$1), [
      'https://example.test/session-2',
      'https://example.test/session-3',
    ]);

    await manager.playItems([next], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors(
      [(file, offset)],
      lookahead: (transcode, offset),
    );
    await tester.pump();
    expect(resolver.calls, 4);
    expect(backend.preloaded, hasLength(3));

    await manager.playItems([file], startPosition: offset, preview: true);
    expect(resolver.calls, 4);
    expect(backend.playedUrls.last, 'https://example.test/session-3');
    await manager.stop();
    expect(service.events, isEmpty);
  });

  testWidgets('a quick tune can use metadata before the encoder handoff', (
    tester,
  ) async {
    final backend = _PreloadingBackend()..parkEnabled = true;
    final resolver = _TestResolver()..playMethod = StreamPlayMethod.transcode;
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    final first = {'Id': 'first', 'Type': 'Movie'};
    final second = {'Id': 'second', 'Type': 'Movie'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    const offset = Duration(minutes: 7);
    await manager.playItems([first], startPosition: offset, preview: true);
    await manager.playItems([second], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors([(next, offset), (first, offset)]);
    await tester.pump();

    expect(backend.parked, ['https://example.test/session-1']);
    expect(resolver.calls, 3);
    expect(service.transcodingStops, isEmpty);
    expect(backend.preloaded, isEmpty);
    await manager.playItems([next], startPosition: offset, preview: true);
    expect(resolver.calls, 3);
    expect(backend.playedUrls.last, 'https://example.test/session-3');
    await manager.stop();
    expect(service.events, isEmpty);
  });

  testWidgets('a parked encoder is handed off to the next channel', (
    tester,
  ) async {
    final backend = _PreloadingBackend()..parkEnabled = true;
    final resolver = _TestResolver()..playMethod = StreamPlayMethod.transcode;
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    final first = {'Id': 'first', 'Type': 'Movie'};
    final second = {'Id': 'second', 'Type': 'Movie'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    const offset = Duration(minutes: 7);
    await manager.playItems([first], startPosition: offset, preview: true);
    await manager.playItems([second], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors([(next, offset), (first, offset)]);
    await tester.pump(const Duration(milliseconds: 700));
    expect(backend.preloaded, isEmpty);
    expect(service.transcodingStops, isEmpty);

    await tester.pump(const Duration(milliseconds: 100));
    expect(service.transcodingStops.single.playSessionId, 'session-1');
    expect(backend.preloaded.single.$1, 'https://example.test/session-3');
    await manager.playItems([next], startPosition: offset, preview: true);
    expect(resolver.calls, 3);
    expect(backend.playedUrls.last, 'https://example.test/session-3');
    await manager.stop();
    expect(service.events, isEmpty);
  });

  testWidgets('lookahead can warm an encoder behind a direct file', (
    tester,
  ) async {
    final backend = _PreloadingBackend()..parkEnabled = true;
    final service = _TestService();
    final current = {'Id': 'current', 'Type': 'Movie'};
    final file = {'Id': 'file', 'Type': 'Episode'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    final resolver = _TestResolver()
      ..playMethodFor = (item) => identical(item, file)
          ? StreamPlayMethod.directPlay
          : StreamPlayMethod.transcode;
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    const offset = Duration(minutes: 7);
    await manager.playItems([current], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors([(file, offset)], lookahead: (next, offset));
    await tester.pump();
    expect(backend.preloaded.map((entry) => entry.$1), [
      'https://example.test/session-2',
      'https://example.test/session-3',
    ]);

    await manager.playItems([file], startPosition: offset, preview: true);
    expect(backend.parked, isEmpty);
    expect(service.transcodingStops.single.playSessionId, 'session-1');
    manager.preparePreviewNeighbors([(next, offset), (current, offset)]);
    await manager.playItems([next], startPosition: offset, preview: true);
    expect(backend.playedUrls.last, 'https://example.test/session-3');
    await manager.stop();
    expect(service.events, isEmpty);
  });

  testWidgets('returning adopts the parked stream at an advanced position', (
    tester,
  ) async {
    final backend = _PreloadingBackend()..parkEnabled = true;
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    final first = {'Id': 'first', 'Type': 'Movie'};
    final second = {'Id': 'second', 'Type': 'Episode'};
    const initial = Duration(minutes: 7);
    const livePosition = Duration(minutes: 7, seconds: 4);
    await manager.playItems([first], startPosition: initial, preview: true);
    manager.preparePreviewNeighbors([(second, initial)]);
    await tester.pump();
    await manager.playItems([second], startPosition: initial, preview: true);
    manager.preparePreviewNeighbors([(first, livePosition)]);
    await tester.pump();
    await manager.playItems(
      [first],
      startPosition: livePosition,
      preview: true,
    );

    expect(resolver.calls, 2);
    expect(backend.playedUrls.last, backend.playedUrls.first);
    expect(backend.startPositions.last, livePosition);
    expect(service.transcodingStops, isEmpty);
    await manager.stop();
    expect(service.transcodingStops.map((r) => r.playSessionId).toSet(), {
      'session-1',
      'session-2',
    });
    expect(service.events, isEmpty);
  });

  testWidgets(
    'warm transcode applies the destination track preferences before tuning',
    (tester) async {
      final backend = _PreloadingBackend();
      final resolver = _TestResolver()..playMethod = StreamPlayMethod.transcode;
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      addTearDown(manager.dispose);
      final current = {'Id': 'current', 'Type': 'Movie'};
      final next = {'Id': 'next', 'Type': 'Episode'};
      const offset = Duration(minutes: 7);
      manager.audioTrackSelector = (item, _, _, preview) =>
          preview && identical(item, next) ? 2 : null;
      manager.subtitleTrackSelector = (item, _, _, _, preview) =>
          preview && identical(item, next) ? 4 : null;
      await manager.playItems([current], startPosition: offset, preview: true);
      manager.preparePreviewNeighbors([(next, offset)]);
      await tester.pump();
      expect(resolver.calls, 3);
      expect(backend.preloaded, [('https://example.test/session-3', offset)]);

      await manager.playItems([next], startPosition: offset, preview: true);
      expect(resolver.calls, 3);
      expect(manager.audioStreamIndex, 2);
      expect(manager.subtitleStreamIndex, 4);
      expect(backend.playedUrls.last, backend.preloaded.single.$1);
      expect(service.events, isEmpty);
      await manager.stop();
    },
  );

  testWidgets(
    'preview tunes release encodings and report only after commitment',
    (tester) async {
      final backend = _TestBackend();
      final service = _TestService();
      final manager = _manager(backend, _TestResolver(), service);
      addTearDown(manager.dispose);
      final first = {'Id': 'first', 'Type': 'Movie'};
      final second = {'Id': 'second', 'Type': 'Episode'};
      const offset = Duration(minutes: 10);
      await manager.playItems([first], startPosition: offset, preview: true);
      await tester.pump(const Duration(seconds: 15));
      await manager.playItems([second], startPosition: offset, preview: true);
      expect(service.events, isEmpty);
      expect(service.transcodingStops.single.playSessionId, 'session-1');
      expect(manager.lastPlayedItem, isNull);
      expect(backend.startPositions, [offset, offset]);

      const watchedPosition = Duration(minutes: 11);
      backend.currentPosition = watchedPosition;
      expect(manager.commitPreview(), isTrue);
      expect(manager.commitPreview(), isFalse);
      expect(service.events, ['start:session-2']);
      expect(service.startPositions, [watchedPosition.inMicroseconds * 10]);
      expect(manager.lastPlayedItem, same(second));
      expect(backend.playedUrls, hasLength(2));

      await tester.pump(const Duration(seconds: 10));
      await manager.stop();
      expect(service.events, [
        'start:session-2',
        'progress:session-2:immediate',
        'progress:session-2:immediate',
        'stop:session-2',
      ]);
    },
  );

  test(
    'starting over discards the preview and reports a new session at zero',
    () async {
      final backend = _TestBackend();
      final service = _TestService();
      final manager = _manager(backend, _TestResolver(), service);
      addTearDown(manager.dispose);
      final item = {'Id': 'movie', 'Type': 'Movie'};
      const offset = Duration(minutes: 12);
      await manager.playItems([item], startPosition: offset, preview: true);
      await manager.playItems([item]);
      expect(backend.startPositions, [offset, Duration.zero]);
      expect(service.events, ['start:session-2']);
      expect(service.transcodingStops.single.playSessionId, 'session-1');
      await manager.stop();
      expect(service.events, ['start:session-2', 'stop:session-2']);
    },
  );

  test(
    'a rejected preview open retries even if the backend has a playhead',
    () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      addTearDown(manager.dispose);
      final gate = Completer<void>();
      backend.playGate = gate;

      final opening = manager.playItems(
        [
          {'Id': 'rejected', 'Type': 'Movie'},
        ],
        startPosition: const Duration(minutes: 3),
        preview: true,
      );
      await pumpEventQueue(times: 5);
      expect(backend.playedUrls, hasLength(1));
      gate.completeError(StateError('open rejected'));
      await opening;

      expect(resolver.requestedDirectPlay, [true, false]);
      expect(manager.bringupState.phase, PlaybackBringupPhase.ready);
      expect(service.transcodingStops.first.playSessionId, 'session-1');
      expect(service.events, isEmpty);
      await manager.stop();
    },
  );

  testWidgets('retro tunes and preloads avoid an automatic subtitle burn-in', (
    tester,
  ) async {
    final backend = _PreloadingBackend();
    final resolver = _TestResolver()
      ..playMethod = StreamPlayMethod.transcode
      ..defaultSubtitleIndex = 4
      ..mediaStreams = [
        {
          'Type': 'Subtitle',
          'Index': 4,
          'Codec': 'pgssub',
          'DeliveryMethod': 'Encode',
        },
      ];
    final service = _TestService();
    final manager = _manager(backend, resolver, service)
      ..subtitleTrackSelector = (_, _, _, _, _) => 4;
    addTearDown(manager.dispose);
    final first = {'Id': 'first', 'Type': 'Movie'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    const offset = Duration(minutes: 3);

    await manager.playItems([first], startPosition: offset, preview: true);
    expect(resolver.requestedSubtitleIndices, [null, -1]);
    expect(backend.playedUrls, ['https://example.test/session-2']);

    manager.preparePreviewNeighbors([(next, offset)]);
    await tester.pump();
    await manager.playItems([next], startPosition: offset, preview: true);
    expect(resolver.requestedSubtitleIndices, [null, -1, null, -1]);
    expect(backend.playedUrls.last, 'https://example.test/session-4');
    expect(service.events, isEmpty);

    await manager.playItems(
      [first],
      subtitleStreamIndex: 4,
      subtitleSelectionExplicit: true,
    );
    expect(resolver.requestedSubtitleIndices.last, 4);
    await manager.stop();
  });

  testWidgets('a tune bypasses a stalled speculative lookup', (tester) async {
    final backend = _PreloadingBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    addTearDown(manager.dispose);
    final current = {'Id': 'current', 'Type': 'Movie'};
    final next = {'Id': 'next', 'Type': 'Movie'};
    final gate = Completer<void>();
    var firstLookup = true;
    resolver.waitForResolution = (item) async {
      if (identical(item, next) && firstLookup) {
        firstLookup = false;
        await gate.future;
      }
    };
    const offset = Duration(minutes: 7);
    await manager.playItems([current], startPosition: offset, preview: true);
    manager.preparePreviewNeighbors([(next, offset)]);
    final opening = manager.playItems(
      [next],
      startPosition: offset,
      preview: true,
    );
    await tester.pump();
    expect(backend.playedUrls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 751));
    await opening;

    expect(backend.playedUrls.last, 'https://example.test/session-3');
    expect(manager.bringupState.phase, PlaybackBringupPhase.ready);
    gate.complete();
    await tester.pump();
    expect(backend.preloaded, isEmpty);
    expect(service.events, isEmpty);
    await manager.stop();
  });

  test('leaving a preview during startup never reports playback', () async {
    final backend = _TestBackend();
    final service = _TestService();
    final manager = _manager(backend, _TestResolver(), service);
    addTearDown(manager.dispose);
    final gate = Completer<void>();
    backend.playGate = gate;
    final opening = manager.playItems([
      {'Id': 'preview', 'Type': 'Movie'},
    ], preview: true);
    try {
      await pumpEventQueue(times: 5);
      expect(backend.playedUrls, hasLength(1));
      await manager.stop();
    } finally {
      gate.complete();
      await opening;
    }
    expect(service.events, isEmpty);
    expect(service.transcodingStops, isNotEmpty);
    expect(manager.commitPreview(), isFalse);
  });

  for (final type in <String>['Movie', 'Episode']) {
    test(
      '$type background stop preserves queue and fresh-resolves position',
      () async {
        final backend = _TestBackend();
        final resolver = _TestResolver();
        final service = _TestService();
        final manager = _manager(backend, resolver, service);
        final item = <String, dynamic>{'Id': type, 'Type': type};

        try {
          await manager.playItems(<dynamic>[item]);
          backend.currentPosition = const Duration(seconds: 90);

          expect(await manager.stopForBackground(item), isTrue);
          expect(manager.queueService.currentItem, same(item));
          expect(service.stoppedResolutions, hasLength(1));
          expect(service.stoppedResolutions.single.playSessionId, 'session-1');

          await manager.startQueuedPlayback(
            startPosition: const Duration(seconds: 90),
            freshResolution: true,
          );

          expect(resolver.calls, 2);
          expect(resolver.requestedMediaSourceIds, <String?>[null, null]);
          expect(resolver.requestedStartTicks, <int?>[
            null,
            const Duration(seconds: 90).inMicroseconds * 10,
          ]);
          expect(backend.playedUrls, <String>[
            'https://example.test/session-1',
            'https://example.test/session-2',
          ]);
          expect(backend.startPositions.last, const Duration(seconds: 90));
        } finally {
          manager.dispose();
        }
      },
    );
  }

  test(
    'live TV cleanup targets old live/transcode ownership and starts fresh',
    () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      final item = <String, dynamic>{
        'Id': 'live-channel',
        'Type': 'LiveTvChannel',
      };

      try {
        await manager.playItems(<dynamic>[item]);
        backend.currentPosition = const Duration(minutes: 20);
        expect(await manager.stopForBackground(item), isTrue);

        expect(service.stoppedResolutions.single.liveStreamId, 'live-1');
        expect(service.transcodingStops.single.playSessionId, 'session-1');

        await manager.startQueuedPlayback(freshResolution: true);
        expect(backend.startPositions.last, Duration.zero);
        expect(backend.playedUrls.last, 'https://example.test/session-2');
        expect(service.events, contains('start:session-2'));
      } finally {
        manager.dispose();
      }
    },
  );

  test('background ownership check cannot stop a replacement item', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    final oldItem = <String, dynamic>{'Id': 'old', 'Type': 'Movie'};
    final replacement = <String, dynamic>{
      'Id': 'replacement',
      'Type': 'Episode',
    };

    try {
      await manager.playItems(<dynamic>[oldItem]);
      manager.queueService.setQueue(<dynamic>[replacement]);

      expect(await manager.stopForBackground(oldItem), isFalse);
      expect(manager.queueService.currentItem, same(replacement));
      expect(service.stoppedResolutions, isEmpty);
      expect(backend.stopCalls, isZero);
    } finally {
      manager.dispose();
    }
  });

  testWidgets(
    'pending progress is discarded on stop and late progress is followed by stop',
    (tester) async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService(stallProgress: true);
      final manager = _manager(backend, resolver, service);
      final item = <String, dynamic>{'Id': 'overlap', 'Type': 'Movie'};

      await manager.playItems(<dynamic>[item]);
      await tester.pump(const Duration(seconds: 10));
      expect(service.progressRequests, hasLength(1));
      manager.reportVolumeState(
        volume: 60,
        isMuted: false,
        reportImmediately: true,
      );

      expect(await manager.stopForBackground(item), isTrue);
      expect(service.events.last, 'stop:session-1');

      service.progressRequests[0].completer.complete();
      await tester.pump();
      expect(service.events.takeLast(2), <String>[
        'progress:session-1:0',
        'stop:session-1',
      ]);

      await tester.pump(const Duration(seconds: 15));
      expect(service.progressRequests, hasLength(1));
      manager.dispose();
    },
  );

  testWidgets(
    'stalled progress cannot block teardown or fresh foreground resume',
    (tester) async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService(stallProgress: true);
      final manager = _manager(backend, resolver, service);
      final item = <String, dynamic>{'Id': 'stalled', 'Type': 'Movie'};

      await manager.playItems(<dynamic>[item]);
      await tester.pump(const Duration(seconds: 10));
      expect(service.progressRequests, hasLength(1));

      await tester.runAsync(() async {
        expect(
          await manager
              .stopForBackground(item)
              .timeout(const Duration(milliseconds: 100)),
          isTrue,
          reason: 'teardown does not await progress',
        );

        await manager
            .startQueuedPlayback(
              startPosition: const Duration(seconds: 30),
              freshResolution: true,
            )
            .timeout(const Duration(milliseconds: 100));
      });
      expect(service.events, contains('start:session-2'));
      manager.reportVolumeState(
        volume: 60,
        isMuted: false,
        reportImmediately: true,
      );
      expect(service.progressRequests, hasLength(2));
      expect(service.progressRequests.last.sessionId, 'session-2');

      service.progressRequests[0].completer.complete();
      await tester.pump();
      expect(service.events.last, 'stop:session-1');
      expect(service.stoppedResolutions.last.playSessionId, isNot('session-2'));

      // The new session's request intentionally never completes. It neither
      // blocks local work nor produces a report requiring compensation.
      manager.dispose();
    },
  );

  testWidgets('only explicit volume changes request prompt reporting', (
    tester,
  ) async {
    final service = _TestService();
    final manager = _manager(_TestBackend(), _TestResolver(), service);
    manager.reportVolumeState(
      volume: 40,
      isMuted: false,
      reportImmediately: true,
    );
    expect(service.reportedVolumes, isEmpty);
    await manager.playItems(<dynamic>[
      {'Id': 'volume', 'Type': 'Movie'},
    ]);
    manager.reportVolumeState(volume: 41, isMuted: false);
    expect(service.reportedVolumes, isEmpty);
    manager.reportVolumeState(
      volume: 42,
      isMuted: false,
      reportImmediately: true,
    );
    expect(service.reportedVolumes, [(42, false)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(service.reportedVolumes, [(42, false), (42, false)]);
    manager.dispose();
  });

  for (final fail in [false, true]) {
    testWidgets(
      'volume reports coalesce behind ${fail ? 'failed' : 'delayed'} progress',
      (tester) async {
        final service = _TestService(stallProgress: true);
        final manager = _manager(_TestBackend(), _TestResolver(), service);
        await manager.playItems(<dynamic>[
          {'Id': 'volume', 'Type': 'Movie'},
        ]);
        manager.reportVolumeState(volume: 40, isMuted: false);
        await tester.pump(const Duration(seconds: 5));
        manager.reportVolumeState(
          volume: 50,
          isMuted: false,
          reportImmediately: true,
        );
        manager.reportVolumeState(
          volume: 60,
          isMuted: false,
          reportImmediately: true,
        );
        await tester.pump(const Duration(seconds: 5));
        expect(service.reportedVolumes, [(40, false)]);
        if (fail) {
          service.progressRequests.single.completer.completeError(
            StateError('offline'),
          );
        } else {
          service.progressRequests.single.completer.complete();
        }
        await tester.pump();
        expect(service.reportedVolumes, [(40, false), (60, false)]);
        manager.reportVolumeState(
          volume: 0,
          isMuted: true,
          reportImmediately: true,
        );
        service.progressRequests.last.completer.complete();
        await tester.pump();
        expect(service.reportedVolumes, [(40, false), (60, false), (0, true)]);
        service.progressRequests.last.completer.complete();
        await tester.pump();
        expect(service.progressRequests, hasLength(3));
        expect(tester.takeException(), isNull);
        manager.dispose();
      },
    );
  }

  testWidgets('disposal discards a queued volume report', (tester) async {
    final service = _TestService(stallProgress: true);
    final manager = _manager(_TestBackend(), _TestResolver(), service);
    await manager.playItems(<dynamic>[
      {'Id': 'volume', 'Type': 'Movie'},
    ]);
    manager.reportVolumeState(
      volume: 40,
      isMuted: false,
      reportImmediately: true,
    );
    manager.reportVolumeState(
      volume: 60,
      isMuted: false,
      reportImmediately: true,
    );
    manager.dispose();
    service.progressRequests.single.completer.complete();
    await tester.pump();
    expect(service.reportedVolumes, [(40, false)]);
    expect(tester.takeException(), isNull);
  });

  test('canonical user stop still clears queue and playback state', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    final item = <String, dynamic>{'Id': 'canonical', 'Type': 'Movie'};

    try {
      await manager.playItems(<dynamic>[item]);
      manager.state.setPosition(const Duration(seconds: 15));
      await manager.stop();

      expect(manager.queueService.currentItem, isNull);
      expect(manager.state.position, Duration.zero);
      expect(backend.stopCalls, 1);
      expect(service.stoppedResolutions.single.playSessionId, 'session-1');
    } finally {
      manager.dispose();
    }
  });

  test(
    'a second failure with nothing new to veto does not resolve again',
    () async {
      final backend = _TestBackend();
      final resolver = _TestResolver();
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      final item = <String, dynamic>{'Id': 'audio', 'Type': 'Movie'};

      try {
        await manager.playItems(<dynamic>[item]);
        // The recovery asks for a transcode, so that is what comes back.
        resolver.playMethod = StreamPlayMethod.transcode;
        backend.emitError(<String, dynamic>{
          'event': 'playerError',
          'recoverable': true,
          'kind': 'unsupported_audio',
        });
        await pumpEventQueue(times: 10);

        expect(resolver.calls, 2);
        expect(resolver.requestedDirectPlay, <bool>[true, false]);

        // No codec on the stream means nothing to veto, so there is no new
        // information a third resolve could act on.
        backend.emitError(<String, dynamic>{
          'event': 'playerError',
          'recoverable': true,
          'kind': 'unsupported_audio',
        });
        await pumpEventQueue(times: 10);

        expect(resolver.calls, 2);
      } finally {
        manager.dispose();
      }
    },
  );

  test('unsupported audio recovers when it lands during startup', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);

    final gate = Completer<void>();
    backend.playGate = gate;

    try {
      final started = manager.playItems(<dynamic>[
        <String, dynamic>{'Id': 'startup', 'Type': 'Movie'},
      ]);
      await pumpEventQueue(times: 5);

      // An audio failure can land before the first play returns, a format the
      // decoder turns down on sight for one, so the recovery has to fire in
      // this window rather than wait on a startup that never finishes.
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_audio',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 2);
      expect(resolver.requestedDirectPlay, <bool>[true, false]);

      // Lets the preempted startup unwind so the handoff runs too.
      gate.complete();
      await started;
      await pumpEventQueue(times: 10);
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
      manager.dispose();
    }
  });

  test('a container error during startup recovers once', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);

    final gate = Completer<void>();
    backend.playGate = gate;

    try {
      final started = manager.playItems(<dynamic>[
        <String, dynamic>{'Id': 'padded', 'Type': 'Movie'},
      ]);
      await pumpEventQueue(times: 5);

      // A malformed container fails in the extractor, before the first play
      // has returned, so the recovery has to fire inside that window.
      resolver.playMethod = StreamPlayMethod.transcode;
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_container',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 2);
      expect(resolver.requestedDirectPlay, <bool>[true, false]);

      // Already transcoding, so a repeat has nowhere further to go.
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_container',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 2);

      gate.complete();
      await started;
      await pumpEventQueue(times: 10);
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
      manager.dispose();
    }
  });

  test('the veto chain runs after a transcode recovery', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver()
      ..mediaStreams = <Map<String, dynamic>>[
        <String, dynamic>{'Type': 'Audio', 'Codec': 'eac3', 'IsDefault': true},
      ];
    final service = _TestService();
    final manager = _manager(backend, resolver, service);

    try {
      await manager.playItems(<dynamic>[
        <String, dynamic>{'Id': 'chain', 'Type': 'Movie'},
      ]);

      // The server answers the transcode request with a different codec the
      // device turns out not to decode either.
      resolver
        ..playMethod = StreamPlayMethod.transcode
        ..mediaStreams = <Map<String, dynamic>>[
          <String, dynamic>{'Type': 'Audio', 'Codec': 'ac3', 'IsDefault': true},
        ];
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_audio',
      });
      await pumpEventQueue(times: 10);
      expect(resolver.calls, 2);
      expect(resolver.requestedDirectPlay, <bool>[true, false]);

      // A second codec vetoed is new information, so it earns one more
      // resolve rather than a dead stop.
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_audio',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 3);
    } finally {
      manager.dispose();
    }
  });

  test('audio offload retry does not trigger server recovery', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver();
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    final item = <String, dynamic>{'Id': 'offload', 'Type': 'Movie'};

    try {
      await manager.playItems(<dynamic>[item]);
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_audio',
        'audioOffloadRetryTriggered': true,
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 1);
      expect(manager.bringupState.phase, isNot(PlaybackBringupPhase.failed));
    } finally {
      manager.dispose();
    }
  });

  test('local media audio failure is surfaced without re-resolving', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver()..isLocalMedia = true;
    final service = _TestService();
    final manager = _manager(backend, resolver, service);
    final item = <String, dynamic>{'Id': 'local', 'Type': 'Movie'};

    try {
      await manager.playItems(<dynamic>[item]);
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_audio',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 1);
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
    } finally {
      manager.dispose();
    }
  });

  test('a transcode that can\'t show the video stops', () async {
    final backend = _TestBackend();
    final resolver = _TestResolver()..playMethod = StreamPlayMethod.transcode;
    final service = _TestService();
    final manager = _manager(backend, resolver, service);

    try {
      await manager.playItems(<dynamic>[
        <String, dynamic>{'Id': 'vc1', 'Type': 'Movie'},
      ]);
      final stopsBefore = backend.stopCalls;
      backend.emitError(<String, dynamic>{
        'event': 'playerError',
        'recoverable': true,
        'kind': 'unsupported_video',
        'message': 'The stream has no video track the player can read',
      });
      await pumpEventQueue(times: 10);

      expect(resolver.calls, 1);
      expect(backend.stopCalls, greaterThan(stopsBefore));
      expect(manager.bringupState.phase, PlaybackBringupPhase.failed);
      expect(manager.bringupState.error, unsupportedVideoError);
    } finally {
      manager.dispose();
    }
  });

  test(
    'already-transcoded audio is retried after vetoing its selected codec',
    () async {
      final backend = _TestBackend();
      final resolver = _TestResolver()
        ..playMethod = StreamPlayMethod.transcode
        ..mediaStreams = <Map<String, dynamic>>[
          <String, dynamic>{
            'Type': 'Audio',
            'Codec': 'eac3',
            'IsDefault': true,
          },
        ];
      final service = _TestService();
      final manager = _manager(backend, resolver, service);
      final item = <String, dynamic>{'Id': 'transcoded', 'Type': 'Movie'};

      try {
        await manager.playItems(<dynamic>[item]);
        backend.emitError(<String, dynamic>{
          'event': 'playerError',
          'recoverable': true,
          'kind': 'unsupported_audio',
        });
        await pumpEventQueue(times: 10);

        expect(resolver.calls, 2);
        expect(resolver.requestedDirectPlay, <bool>[true, false]);
      } finally {
        manager.dispose();
      }
    },
  );
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
