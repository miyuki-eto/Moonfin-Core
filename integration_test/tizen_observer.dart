// Read-only, test-only observer. Normal builds never import this entrypoint.
// Input comes from Samsung's authorized remote channel, not synthetic keys.
// Screenshots capture Flutter UI, excluding Samsung's hardware video plane.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/main.dart' as app;
import 'package:moonfin/ui/screens/playback/retro_tv_actions.dart';
import 'package:moonfin/ui/screens/playback/retro_tv_browser.dart';
import 'package:moonfin/ui/screens/playback/video_player_screen.dart';
import 'package:moonfin/ui/tv/tv26_button.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:moonfin/util/scroll_sensitivity_binding.dart';
import 'package:playback_core/playback_core.dart';

export 'package:moonfin/main.dart'
    show watchNextBackgroundMain, autoDownloadBackgroundMain;

const _key = String.fromEnvironment('MOONFIN_TV_TEST_KEY');

class _Binding extends ScrollSensitivityBinding {
  final picture = GlobalKey();

  @override
  Widget wrapWithDefaultView(Widget rootWidget) => super.wrapWithDefaultView(
    RepaintBoundary(key: picture, child: rootWidget),
  );
}

String _redact(Object value) => value.toString().replaceAllMapped(
  RegExp(
    r'(api[_-]?key|access[_-]?token|token|password)=([^&\s]+)',
    caseSensitive: false,
  ),
  (match) => '${match[1]}=[redacted]',
);

void main() async {
  if (!PlatformDetection.isTizen || _key.isEmpty) {
    throw StateError('An explicit native observer build/key is required');
  }
  final binding = _Binding();
  var stage = 'starting';
  final timings = <ui.FrameTiming>[];
  final nativeKeys = <String>[];
  final failures = <String>[];
  final events = <String>[];
  void record(Object message) {
    events.add(
      '${DateTime.now().toUtc().toIso8601String()} ${_redact(message)}',
    );
    if (events.length > 100) events.removeAt(0);
  }

  binding.addTimingsCallback((frames) {
    timings.addAll(frames);
    if (timings.length > 240) timings.removeRange(0, timings.length - 240);
  });
  HardwareKeyboard.instance.addHandler((event) {
    if (event is KeyDownEvent) {
      nativeKeys.add(event.logicalKey.keyLabel);
      if (nativeKeys.length > 30) nativeKeys.removeAt(0);
    }
    return false;
  });
  Map<String, dynamic> state() {
    final texts = <String>[];
    final widgets = <String, int>{};
    final buttons = <String>[];
    final routes = <String>[];
    final extra = <String, dynamic>{};
    void visit(Element element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        return;
      }
      final widget = element.widget;
      final name = widget.runtimeType.toString();
      widgets[name] = (widgets[name] ?? 0) + 1;
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        if (text.isNotEmpty && !texts.contains(text)) texts.add(text);
      }
      if (widget is Tv26Button) buttons.add(widget.label);
      if (name.endsWith('Screen')) routes.add(name);
      if (widget is VideoPlayerScreen) extra['retroTv'] = widget.retroTv;
      if (widget is RetroTvChannelBrowser) {
        extra['guide'] = {
          'playing': widget.playing.number,
          'channels': widget.channels.length,
        };
      }
      if (widget is RetroTvActionMenu) {
        extra['actions'] = {
          'programme': widget.program.item.name,
          'enabled': widget.actionsEnabled,
        };
      }
      element.visitChildren(visit);
    }

    binding.rootElement?.visitChildren(visit);
    final focus = FocusManager.instance.primaryFocus;
    final label = focus?.context
        ?.findAncestorWidgetOfExactType<Tv26Button>()
        ?.label;
    final manager = GetIt.instance.isRegistered<PlaybackManager>()
        ? GetIt.instance<PlaybackManager>()
        : null;
    final backend = manager?.backend;
    final item = manager?.queueService.currentItem;
    final resolution = manager?.currentResolution;
    return {
      'time': DateTime.now().toUtc().toIso8601String(),
      'stage': stage,
      'profileMode': kProfileMode,
      'physicalSize': {
        'width': binding.platformDispatcher.views.first.physicalSize.width,
        'height': binding.platformDispatcher.views.first.physicalSize.height,
        'dpr': binding.platformDispatcher.views.first.devicePixelRatio,
      },
      'screens': routes,
      'texts': texts.take(250).toList(),
      'buttons': buttons,
      'focus': label ?? focus?.debugLabel,
      'focusWidget': focus?.context?.widget.runtimeType.toString(),
      'modals': widgets['Dialog'] ?? 0,
      'pgsOverlay': widgets['PgsSubtitleView'] ?? 0,
      'nativeKeys': nativeKeys.toList(),
      'exceptions': failures.toList(),
      'events': events.toList(),
      'frames': timings
          .map(
            (f) => {
              'buildUs': f.buildDuration.inMicroseconds,
              'rasterUs': f.rasterDuration.inMicroseconds,
              'totalUs': f.totalSpan.inMicroseconds,
            },
          )
          .toList(),
      if (backend != null)
        'playback': {
          'backend': backend.runtimeType.toString(),
          'positionMs': backend.position.inMilliseconds,
          'durationMs': backend.duration.inMilliseconds,
          'playing': backend.isPlaying,
          'buffering': backend.isBuffering,
          'bringup': manager!.bringupState.phase.name,
          'error': manager.bringupState.error,
          'audioIndex': manager.audioStreamIndex,
          'subtitleIndex': manager.subtitleStreamIndex,
          if (resolution != null)
            'subtitleDelivery': [
              for (final stream in resolution.mediaStreams)
                if (stream['Type'] == 'Subtitle' && stream['Index'] == manager.subtitleStreamIndex)
                  {for (final key in ['Codec', 'DeliveryMethod', 'IsExternal', 'SupportsExternalStream'])
                    if (stream[key] != null) key: stream[key]},
            ],
          if (item is AggregatedItem)
            'item': {'id': item.id, 'name': item.name, 'type': item.type},
          if (resolution != null) 'method': resolution.playMethod.name,
          if (resolution != null) 'reasons': resolution.transcodingReasons,
          if (resolution != null) 'container': resolution.container,
          if (resolution != null)
            'deliveredVideo': resolution.deliveredFormat?.videoCodec,
          if (resolution != null)
            'deliveredAudio': resolution.deliveredFormat?.audioCodec,
        },
      ...extra,
    };
  }

  // Startup does not depend on a connection to the Mac.
  final startup = app
      .startMediaApp(binding: binding)
      .then(
        (_) {
          stage = 'ready';
          final manager = GetIt.instance<PlaybackManager>();
          manager.setDiagnosticLogger(record);
          manager.backend?.errorStream?.listen(record);
          String? previousBringup;
          manager.bringupStateStream.listen((state) {
            final current = '${state.phase.name}: ${state.error}';
            if (current != previousBringup) {
              previousBringup = current;
              record(current);
            }
          });
          final previousError = FlutterError.onError;
          FlutterError.onError = (details) {
            failures.add(_redact(details.exception));
            previousError?.call(details);
          };
        },
        onError: (Object error, StackTrace stack) {
          stage = 'startup-error';
          failures.add(_redact(error));
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        },
      );
  // The Mac connects outbound to the TV. No HTTP writes or input API exists.
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8791);
  await startup;
  await for (final request in server) {
    request.response.headers.contentType = ContentType.json;
    try {
      if (request.method != 'GET' ||
          request.headers.value('X-Media-Test-Key') != _key) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write(jsonEncode({'error': 'denied'}));
      } else if (request.uri.path == '/health') {
        request.response.write(jsonEncode({'stage': stage}));
      } else if (request.uri.path == '/streamStatus') {
        final resolution = GetIt.instance<PlaybackManager>().currentResolution;
        if (resolution == null) throw StateError('No current stream');
        final uri = Uri.parse(resolution.streamUrl);
        final result = <String, dynamic>{
          'path': uri.path,
          'authInUrl': uri.queryParameters.keys.any(
            (key) => {'apikey', 'api_key'}.contains(key.toLowerCase()),
          ),
        };
        if (uri.path.endsWith('.m3u8')) {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5);
          try {
            Future<({int status, String body})> playlist(Uri address) async {
              final get = await client.getUrl(address);
              resolution.requestHeaders.forEach(get.headers.set);
              final response = await get.close().timeout(
                const Duration(seconds: 8),
              );
              final body = await response
                  .transform(utf8.decoder)
                  .join()
                  .timeout(const Duration(seconds: 8));
              return (status: response.statusCode, body: body);
            }

            final master = await playlist(uri);
            result['masterStatus'] = master.status;
            result['masterIsPlaylist'] = master.body.startsWith('#EXTM3U');
            final entries = const LineSplitter()
                .convert(master.body)
                .where((line) => line.isNotEmpty && !line.startsWith('#'));
            if (entries.isNotEmpty &&
                Uri.parse(entries.first).path.endsWith('.m3u8')) {
              final media = await playlist(uri.resolve(entries.first));
              result['mediaStatus'] = media.status;
              result['mediaIsPlaylist'] = media.body.startsWith('#EXTM3U');
              result['segments'] = '#EXTINF:'.allMatches(media.body).length;
            }
          } finally {
            client.close(force: true);
          }
        }
        request.response.write(jsonEncode(result));
      } else if (request.uri.path == '/state') {
        final output = state();
        if (request.uri.queryParameters['screenshot'] == '1') {
          try {
            binding.scheduleFrame();
            await binding.endOfFrame.timeout(const Duration(seconds: 5));
            final boundary =
                binding.picture.currentContext?.findRenderObject()
                    as RenderRepaintBoundary?;
            if (boundary == null) throw StateError('No rendered root');
            final image = await boundary
                .toImage(pixelRatio: 1)
                .timeout(const Duration(seconds: 8));
            try {
              final bytes = await image
                  .toByteData(format: ui.ImageByteFormat.png)
                  .timeout(const Duration(seconds: 8));
              if (bytes != null) {
                output['screenshot'] = base64Encode(bytes.buffer.asUint8List());
              }
            } finally {
              image.dispose();
            }
          } catch (error) {
            output['screenshotError'] = _redact(error);
          }
        }
        request.response.write(jsonEncode(output));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'unknown route'}));
      }
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': _redact(error)}));
    } finally {
      await request.response.close();
    }
  }
}
