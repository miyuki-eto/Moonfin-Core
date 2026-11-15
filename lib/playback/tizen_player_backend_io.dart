import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:playback_core/playback_core.dart';
import 'package:video_player_videohole/video_player.dart' as vp;

import '../preference/user_preferences.dart';
import '../ui/tv/tv_reveal_transition.dart';
import '../ui/widgets/tizen_video_view.dart';
import '../ui/widgets/pgs_subtitle_view.dart';
import 'pgs/pgs_decoder.dart';
import 'subtitle_style.dart';
import 'subtitle_view_config.dart' show subtitleStrokeShadows;
import 'tizen_player_profile.dart';
import 'web_subtitle_text.dart' show srtAlignmentTag;

/// Native Samsung Media Player; the shared PlaybackManager still owns sessions,
/// language selection, resume positions and Retro TV's preview/progress rules.
/// Only one decoder is opened until standby playback is verified on the TV.
class TizenPlayerBackend extends PlayerBackend
    with ChangeNotifier, SubtitleDelayState
    implements
        SubtitleLoadingBackend,
        PlayerOpenLatency,
        AsyncPgsSubtitleBackend {
  TizenPlayerBackend(this._prefs);

  final UserPreferences _prefs;
  vp.VideoPlayerController? _controller;
  Future<void> _operations = Future.value();
  Future<void> _ready = Future.value();
  Completer<void>? _openInterrupted;
  int _generation = 0;
  bool _disposed = false;
  bool _playIntent = false;
  double _speed = 1;
  double _volume = 100;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  String? _lastError;
  int? _subtitleIndex;
  int _subtitleGeneration = 0;
  bool _subtitleLoading = false;
  List<vp.Caption>? _externalCues;
  final _nativeCues = <vp.Caption>[];
  vp.Caption? _lastNativeCaption;
  PgsTimeline? _pgsTrack;
  bool _pgsSelected = false;
  String? _subtitleError;
  final _sidecars = <({String url, String? codec})>[];
  http.Client? _subtitleClient;
  late SubtitleStyle _style = SubtitleStyle.resolve(_prefs, isHdr: false);

  final _positionCtl = StreamController<Duration>.broadcast();
  final _durationCtl = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _bufferingCtl = StreamController<bool>.broadcast();
  final _completedCtl = StreamController<bool>.broadcast();
  final _errorCtl = StreamController<Map<String, dynamic>>.broadcast();
  final _subtitleLoadingCtl = StreamController<bool>.broadcast();

  // Preserve ordering across stop/open, including a late native prepare. A
  // canceled source must release its decoder before another one is created.
  Future<void> _enqueue(Future<void> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // The caller receives the error; it must not poison the next operation.
      },
    );
    return result;
  }

  bool _owns(int generation, vp.VideoPlayerController controller) =>
      !_disposed && generation == _generation && _controller == controller;

  void _interruptOpen() {
    final interrupted = _openInterrupted;
    if (interrupted != null && !interrupted.isCompleted) interrupted.complete();
  }

  void _onValue() {
    final value = _controller?.value;
    if (_disposed || value == null) return;
    final caption = value.caption;
    if (!identical(_lastNativeCaption, caption)) {
      _lastNativeCaption = caption;
      if (caption.text.isNotEmpty) _nativeCues.add(caption);
    }
    final oldest = value.position - const Duration(seconds: 15);
    _nativeCues.removeWhere((cue) => cue.end < oldest);
    if (_nativeCues.length > 100) {
      _nativeCues.removeRange(0, _nativeCues.length - 100);
    }
    if (value.position != _position) {
      _position = value.position;
      _positionCtl.add(_position);
    }
    if (value.duration.end != _duration) {
      _duration = value.duration.end;
      _durationCtl.add(_duration);
    }
    if (value.isPlaying != _playing) {
      _playing = value.isPlaying;
      _playingCtl.add(_playing);
    }
    if (value.isBuffering != _buffering) {
      _buffering = value.isBuffering;
      _bufferingCtl.add(_buffering);
    }
    if (value.isCompleted && !_completed) _completedCtl.add(true);
    _completed = value.isCompleted;
    if (value.hasError && value.errorDescription != _lastError) {
      _lastError = value.errorDescription;
      _errorCtl.add({'message': _lastError ?? 'Samsung playback failed'});
    }
  }

  Future<void> _releaseController() async {
    final controller = _controller;
    _controller = null;
    if (!_disposed) notifyListeners();
    if (controller != null) {
      controller.removeListener(_onValue);
      await controller.dispose();
    }
    _nativeCues.clear();
    _lastNativeCaption = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _buffering = false;
    _completed = false;
    if (!_disposed) {
      _positionCtl.add(Duration.zero);
      _durationCtl.add(Duration.zero);
      _playingCtl.add(false);
      _bufferingCtl.add(false);
    }
  }

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) {
    final generation = ++_generation;
    _interruptOpen();
    _playIntent = false;
    return _ready = _enqueue(() async {
      await _releaseController();
      if (_disposed || generation != _generation) return;
      final payload = mediaItem is Map ? mediaItem : const {};
      final url = mediaItem is String ? mediaItem : payload['url'] as String?;
      if (url == null || !{'http', 'https'}.contains(Uri.parse(url).scheme)) {
        throw ArgumentError('Samsung playback requires an HTTP(S) source');
      }
      _cancelSubtitleLoad();
      _externalCues = null;
      _pgsTrack = null;
      _pgsSelected = false;
      _subtitleError = null;
      _subtitleIndex = null;
      _setSubtitleLoading(false);
      _sidecars.clear();
      updateSubtitleDelaySession(payload['subtitleDelaySessionId'] as int?);
      final range = (payload['videoRangeType'] as String? ?? '').toUpperCase();
      _style = SubtitleStyle.resolve(_prefs, isHdr: range.contains('HDR'));
      final declared = payload['externalSubtitles'];
      if (declared is List) {
        for (final sub in declared.whereType<Map>()) {
          final subtitleUrl = sub['url'];
          if (subtitleUrl is String) {
            _sidecars.add((url: subtitleUrl, codec: sub['codec'] as String?));
          }
        }
      }
      final headers = payload['headers'];
      _playIntent = payload['autoPlay'] != false;
      final controller = vp.VideoPlayerController.network(
        url,
        httpHeaders: headers is Map ? Map<String, String>.from(headers) : {},
      );
      _controller = controller;
      final interrupted = Completer<void>();
      _openInterrupted = interrupted;
      _lastError = null;
      controller.addListener(_onValue);
      notifyListeners();
      try {
        // CAPI creates its player before awaiting prepare. Disposal can cancel
        // preparation without waiting for an initialized event that may never
        // arrive. The controller still drains creation before native disposal.
        await Future.any([controller.initialize(), interrupted.future])
            .timeout(maxOpenLatency);
        if (!_owns(generation, controller)) return;
        await controller.setVolume((_volume / 100).clamp(0.0, 1.0));
        if (!_owns(generation, controller)) return;
        if (_speed != 1) await controller.setPlaybackSpeed(_speed);
        if (!_owns(generation, controller)) return;
        // Select before the first play, rather than audibly starting on the
        // container default while the manager applies the saved language.
        final audioOrdinal = payload['audioTrackOrdinal'] as int?;
        if (audioOrdinal != null) await _selectAudio(controller, audioOrdinal);
        if (!_owns(generation, controller)) return;
        // CAPI ignores AVPlay's startPosition option. Seek the prepared player
        // before its first frame, including transcodes and paused TV previews.
        if (startPosition > Duration.zero) {
          await Future.any([
            controller.seekTo(startPosition),
            interrupted.future,
          ]).timeout(maxOpenLatency);
          if (!_owns(generation, controller)) return;
        }
        if (_playIntent) await controller.play();
        _onValue();
      } catch (_) {
        await _releaseController();
        rethrow;
      } finally {
        if (identical(_openInterrupted, interrupted)) _openInterrupted = null;
        if (!_owns(generation, controller) && _controller == controller) {
          await _releaseController();
        }
      }
    });
  }

  @override
  Future<void> stop() {
    ++_generation;
    _interruptOpen();
    _cancelSubtitleLoad();
    _playIntent = false;
    _externalCues = null;
    _pgsTrack = null;
    _pgsSelected = false;
    _subtitleError = null;
    _setSubtitleLoading(false);
    return _enqueue(_releaseController);
  }

  @override
  Future<void> pause() async {
    _playIntent = false;
    await _controller?.pause();
  }

  @override
  Future<void> resume() async {
    final generation = _generation;
    await _ready;
    if (_disposed || generation != _generation) return;
    _playIntent = true;
    await _controller?.play();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final generation = _generation;
    await _ready;
    if (_disposed || generation != _generation) return;
    _nativeCues.clear();
    await _controller?.seekTo(position);
  }

  @override
  Future<void> waitForTracksReady() => _ready;
  @override
  Future<void> waitForEmbeddedSubtitleCount(int count) => _ready;

  Future<void> _selectAudio(
    vp.VideoPlayerController controller,
    int index,
  ) async {
    final tracks = await controller.audioTracks ?? [];
    if (index < 1 || index > tracks.length) {
      throw StateError('Samsung audio track $index is unavailable');
    }
    if (!await controller.setTrackSelection(tracks[index - 1])) {
      throw StateError('Samsung audio track selection failed');
    }
  }

  @override
  Future<void> setAudioTrack(int index) async {
    final generation = _generation;
    await _ready;
    if (_disposed || generation != _generation) return;
    final controller = _controller;
    if (controller != null) await _selectAudio(controller, index);
  }

  @override
  Future<void> setSubtitleTrack(
    int index, {
    bool isBitmapSubtitle = false,
    String? subtitleCodec,
    bool isExternalSubtitle = false,
    String? externalSubtitleUrl,
  }) async {
    _cancelSubtitleLoad();
    final token = _subtitleGeneration;
    await _ready;
    if (_disposed || token != _subtitleGeneration) return;
    final controller = _controller;
    if (controller == null) return;
    _pgsTrack = null;
    _pgsSelected = MediaStreamResolver.isPgsCodec(subtitleCodec);
    _subtitleError = null;
    _nativeCues.clear();
    _externalCues = null;
    notifyListeners();
    if (_pgsSelected) {
      _subtitleIndex = index;
      if (externalSubtitleUrl == null) {
        _subtitleError = 'This subtitle track has no downloadable PGS file.';
        notifyListeners();
        return;
      }
      // Track selection commits immediately. The loading stream owns the
      // download; menus, progress reporting and channel changes stay usable.
      unawaited(_loadPgs(externalSubtitleUrl));
      notifyListeners();
      return;
    } else if (isExternalSubtitle && externalSubtitleUrl != null) {
      await _loadSidecar(externalSubtitleUrl, subtitleCodec);
    } else {
      final tracks = await controller.textTracks ?? [];
      if (_disposed ||
          token != _subtitleGeneration ||
          controller != _controller) {
        return;
      }
      if (index > tracks.length && index - tracks.length <= _sidecars.length) {
        final sidecar = _sidecars[index - tracks.length - 1];
        await _loadSidecar(sidecar.url, sidecar.codec);
      } else {
        if (index < 1 || index > tracks.length) {
          throw StateError('Samsung subtitle track $index is unavailable');
        }
        if (!await controller.setTrackSelection(tracks[index - 1])) {
          throw StateError('Samsung subtitle track selection failed');
        }
        _externalCues = null;
        _nativeCues.clear();
        _setSubtitleLoading(false);
      }
    }
    if (!_disposed &&
        token == _subtitleGeneration &&
        controller == _controller) {
      _subtitleIndex = index;
      notifyListeners();
    }
  }

  Future<void> _loadPgs(String url) async {
    final token = _subtitleGeneration;
    final client = http.Client();
    _subtitleClient = client;
    _setSubtitleLoading(true);
    try {
      // Server extraction can be slow. This runs after video starts, matching
      // Moonfin's canvas path; it never gates native player readiness.
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(minutes: 2));
      if (_disposed || token != _subtitleGeneration) return;
      if (response.statusCode != 200) {
        throw StateError('PGS HTTP ${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      await response.stream
          .forEach((chunk) {
            if (bytes.length + chunk.length > 64 * 1024 * 1024) {
              throw const FormatException('PGS subtitle file exceeds 64 MiB');
            }
            bytes.add(chunk);
          })
          .timeout(const Duration(minutes: 2));
      if (_disposed || token != _subtitleGeneration) return;
      final track = await compute(decodePgs, bytes.takeBytes());
      if (_disposed || token != _subtitleGeneration) return;
      _pgsTrack = track;
      notifyListeners();
    } catch (error) {
      if (_disposed || token != _subtitleGeneration) return;
      _subtitleError =
          'Subtitles could not be loaded. Select another track or retry.';
      debugPrint('PGS subtitle load failed: ${error.runtimeType}');
      notifyListeners();
    } finally {
      client.close();
      if (token == _subtitleGeneration) {
        _subtitleClient = null;
        _setSubtitleLoading(false);
      }
    }
  }

  Future<void> _loadSidecar(String url, String? codec) async {
    final token = _subtitleGeneration;
    final generation = _generation;
    final client = http.Client();
    _subtitleClient = client;
    _setSubtitleLoading(true);
    try {
      final response = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('Subtitle download failed (${response.statusCode})');
      }
      final vp.ClosedCaptionFile file;
      final body = utf8.decode(response.bodyBytes).replaceFirst('\uFEFF', '');
      switch (codec?.toLowerCase()) {
        case 'srt':
        case 'subrip':
          file = vp.SubRipCaptionFile(body);
        case 'vtt':
        case 'webvtt':
        case null:
          file = body.trimLeft().startsWith('WEBVTT')
              ? vp.WebVTTCaptionFile(body)
              : vp.SubRipCaptionFile(body);
        default:
          throw UnsupportedError('Samsung sidecar format: $codec');
      }
      if (_disposed ||
          token != _subtitleGeneration ||
          generation != _generation) {
        return;
      }
      _externalCues = [
        for (final cue in file.captions)
          vp.Caption(
            number: cue.number,
            start: cue.start,
            end: cue.end,
            text:
                html
                    .parseFragment(cue.text.replaceFirst(srtAlignmentTag, ''))
                    .text ??
                '',
          ),
      ];
      notifyListeners();
    } catch (_) {
      if (_disposed ||
          token != _subtitleGeneration ||
          generation != _generation) {
        return;
      }
      rethrow;
    } finally {
      client.close();
      if (token == _subtitleGeneration) {
        _subtitleClient = null;
        _setSubtitleLoading(false);
      }
    }
  }

  void _cancelSubtitleLoad() {
    ++_subtitleGeneration;
    _subtitleClient?.close();
    _subtitleClient = null;
    _setSubtitleLoading(false);
  }

  void _setSubtitleLoading(bool value) {
    if (_disposed || _subtitleLoading == value) return;
    _subtitleLoading = value;
    _subtitleLoadingCtl.add(value);
  }

  @override
  Future<void> addExternalSubtitle(
    String url, {
    String? title,
    String? language,
    String? codec,
  }) async {
    if (!_sidecars.any((sub) => sub.url == url)) {
      _sidecars.add((url: url, codec: codec));
    }
  }

  @override
  Future<void> disableSubtitleTrack() async {
    _cancelSubtitleLoad();
    _subtitleIndex = -1;
    _externalCues = null;
    _pgsTrack = null;
    _pgsSelected = false;
    _subtitleError = null;
    _setSubtitleLoading(false);
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    subtitleDelaySeconds = seconds;
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> configureSubtitleStyle({
    int? textColor,
    int? backgroundColor,
    int? strokeColor,
    double? fontSize,
    int? fontWeight,
    double? verticalOffset,
  }) async {
    _style = SubtitleStyle(
      textColor: textColor ?? _style.textColor,
      backgroundColor: backgroundColor ?? _style.backgroundColor,
      strokeColor: strokeColor ?? _style.strokeColor,
      fontSize: fontSize ?? _style.fontSize,
      fontWeight: fontWeight ?? _style.fontWeight,
      verticalOffset: verticalOffset ?? _style.verticalOffset,
    );
    if (!_disposed) notifyListeners();
  }

  Widget buildView({bool ready = true, BoxFit fit = BoxFit.contain}) =>
      AnimatedBuilder(
        animation: this,
        builder: (context, _) {
          final controller = _controller;
          if (controller == null) return const ColoredBox(color: Colors.black);
          return ValueListenableBuilder<vp.VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) => TvContentReveal(
              key: ObjectKey(controller),
              nativeSurface: true,
              ready: ready && value.isInitialized,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TizenVideoView(controller: controller, fit: fit),
                  if (_subtitleIndex != null && _subtitleIndex != -1)
                    _buildSubtitle(context, value, fit),
                ],
              ),
            ),
          );
        },
      );

  Widget _buildSubtitle(
    BuildContext context,
    vp.VideoPlayerValue value,
    BoxFit fit,
  ) {
    final at =
        value.position -
        Duration(
          microseconds: (subtitleDelaySeconds * Duration.microsecondsPerSecond)
              .round(),
        );
    final pgs = _pgsTrack;
    if (_pgsSelected && pgs != null && _subtitleError == null) {
      return PgsSubtitleView(
        track: pgs,
        position: at,
        fit: fit,
        onError: (error) {
          if (_disposed || !identical(_pgsTrack, pgs)) return;
          _subtitleError =
              'Subtitles could not be decoded. Select another track.';
          notifyListeners();
        },
      );
    }
    final cues = _pgsSelected
        ? const <vp.Caption>[]
        : (_externalCues ?? _nativeCues);
    final text =
        _subtitleError ??
        cues
            .where((cue) => cue.start <= at && cue.end >= at)
            .map((cue) => cue.text)
            .join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    final size = (_style.fontSize / 24) * 32;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + _style.verticalOffset * MediaQuery.sizeOf(context).height * .5,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(_style.textColor),
              backgroundColor: Color(_style.backgroundColor),
              fontSize: size,
              height: 1.4,
              fontWeight: _style.fontWeight >= 700
                  ? FontWeight.bold
                  : FontWeight.normal,
              shadows: subtitleStrokeShadows(Color(_style.strokeColor), size),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => buildTizenPlayerProfile(_prefs);
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
    _speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100);
    await _controller?.setVolume(_volume / 100);
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    if (seconds != 0) throw UnsupportedError('Samsung audio delay');
  }

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {
    if (mode == SubtitleRendererMode.assOverlay) {
      throw UnsupportedError('Samsung ASS subtitles require server burn-in');
    }
  }

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  // The hardware player does not expose a buffered media-time range.
  @override
  Duration get buffer => _position;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isBuffering => _buffering;
  @override
  bool get playWhenReady => _playIntent;
  @override
  double get playbackSpeed => _speed;
  @override
  Stream<Duration> get positionStream => _positionCtl.stream;
  @override
  Stream<Duration> get durationStream => _durationCtl.stream;
  @override
  Stream<Duration> get bufferStream => _positionCtl.stream;
  @override
  Stream<bool> get playingStream => _playingCtl.stream;
  @override
  Stream<bool> get bufferingStream => _bufferingCtl.stream;
  @override
  Stream<bool> get completedStream => _completedCtl.stream;
  @override
  Stream<Map<String, dynamic>> get errorStream => _errorCtl.stream;
  @override
  bool get supportsRuntimeTrackSelection => true;
  @override
  bool get supportsDirectPlayAudioSwitch => true;
  @override
  bool get nativelyHandlesStartPosition => true;
  @override
  Duration get maxOpenLatency => const Duration(seconds: 30);
  @override
  bool get canRenderBitmapSubtitles => true;
  @override
  bool get loadsEmbeddedPgsAsFiles => true;
  @override
  bool get supportsSmoothRateChange => false;
  @override
  int? get activeSubtitleTrackIndex => _subtitleIndex;
  @override
  Future<int?> getActiveSubtitleTrackIndexAsync() async => _subtitleIndex;
  @override
  bool get isSubtitleLoading => _subtitleLoading;
  @override
  Stream<bool> get subtitleLoadingStream => _subtitleLoadingCtl.stream;

  @override
  void dispose() {
    if (_disposed) return;
    ++_generation;
    _interruptOpen();
    _cancelSubtitleLoad();
    _disposed = true;
    // Cancel pending prepare, then release the one owned native player.
    unawaited(
      _enqueue(_releaseController)
          .whenComplete(() async {
            await Future.wait([
              _positionCtl.close(),
              _durationCtl.close(),
              _playingCtl.close(),
              _bufferingCtl.close(),
              _completedCtl.close(),
              _errorCtl.close(),
              _subtitleLoadingCtl.close(),
            ]);
          })
          .catchError((Object error, StackTrace stack) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                context: ErrorDescription('while releasing the Samsung player'),
              ),
            );
          }),
    );
    super.dispose();
  }
}
