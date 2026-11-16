import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../../playback/media3_player_backend.dart';
import '../../../util/platform_detection.dart';
import '../../tv/tv_reveal_transition.dart';
import 'retro_tv_dial.dart';
import 'retro_tv_details.dart';
import 'retro_tv_card.dart';
import 'retro_tv_browser.dart';
import 'retro_tv_actions.dart';

export 'retro_tv_card.dart';
export 'retro_tv_actions.dart';

const _fadeOutDuration = AppMotion.normal;

class RetroTvSession extends ChangeNotifier {
  RetroTvSession(this._manager, MediaServerClient client, String serverId)
    : _dial = RetroTvDial.forClient(client, serverId);

  Duration get _tuneDeadline {
    final backend = _manager.backend;
    if (backend case PlayerOpenLatency(:final maxOpenLatency)) {
      return maxOpenLatency;
    }
    return const Duration(seconds: 12);
  }

  static const _catalogRefresh = Duration(hours: 6);

  final PlaybackManager _manager;
  final RetroTvDial _dial;
  RetroChannel? _channel;
  RetroChannel? _previousChannel;
  RetroProgram? _program;
  Timer? _programEnd;
  Timer? _catalogTimer;
  int _direction = 1;
  int _switches = 0;
  bool _loading = false;
  bool _tuning = false;
  bool _hasPicture = false;
  Uint8List? _transitionFrame;
  bool reducedMotion = false;
  Completer<bool>? _supersededTune;
  bool _closed = false;
  String? _error;

  RetroChannel? get channel => _channel;
  RetroChannel? get previousChannel => _previousChannel;
  List<RetroChannel> get channels => _dial.channels;
  RetroProgram? get program => _program;
  RetroProgram? get nextProgram => _channel?.next;
  bool get busy => _loading || _tuning;
  int get switches => _switches;
  String? get error => _error;
  Uint8List? get transitionFrame => _transitionFrame;

  Future<void> start() async {
    if (_closed || busy) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _dial.loadInitial();
      if (_closed) return;
      _dial.update(DateTime.timestamp());
      _channel = _dial.channels.firstOrNull;
      if (_channel == null) _error = 'No movies or episodes to tune into';
    } catch (error) {
      debugPrint('Retro TV programming load failed: $error');
      _error = 'Couldn’t load channels';
    } finally {
      _loading = false;
      if (!_closed) {
        if (_channel != null) {
          syncProgram();
          unawaited(_refillCatalog());
          _catalogTimer ??= Timer.periodic(
            _catalogRefresh,
            (_) => unawaited(_refillCatalog()),
          );
        } else {
          notifyListeners();
        }
      }
    }
  }

  Future<void> _refillCatalog() async {
    try {
      await _dial.refill();
      if (!_closed) syncProgram();
    } catch (error) {
      debugPrint('Retro TV catalog refresh failed: $error');
    }
  }

  void move(int step) {
    final current = _channel;
    if (_closed || _loading || current == null) return;
    final now = DateTime.timestamp();
    _dial.update(now);
    final channels = _dial.channels;
    if (channels.length < 2) return;
    final index = channels.indexOf(current);
    tune(channels[(index + step) % channels.length]);
    _direction = step;
  }

  void tune(RetroChannel target) {
    if (_closed || _loading || !_dial.channels.contains(target)) return;
    final now = DateTime.timestamp();
    _dial.update(now);
    if (identical(target, _channel)) {
      syncProgram();
      if (_error != null) retry();
      return;
    }
    final channels = _dial.channels;
    _direction = channels.indexOf(target) < channels.indexOf(_channel!)
        ? -1
        : 1;
    _previousChannel = _channel;
    _channel = target;
    _switches++;
    _syncProgram(now);
  }

  void syncProgram() {
    if (_closed || _channel == null) return;
    final now = DateTime.timestamp();
    _dial.update(now);
    _syncProgram(now);
  }

  void _syncProgram(DateTime now) {
    final current = _channel!.now;
    final changed = !identical(current, _program);
    if (!changed && _programEnd?.isActive == true) return;
    _program = current;
    _programEnd?.cancel();
    _programEnd = Timer(current.endsAt.difference(now), syncProgram);
    if (!changed) return;
    _interruptTune();
    retry();
  }

  void retry() {
    if (_closed) return;
    if (_program == null) {
      unawaited(start());
    } else if (!_tuning) {
      unawaited(_tune());
    } else {
      notifyListeners();
    }
  }

  Future<void> _tune() async {
    _tuning = true;
    try {
      while (!_closed) {
        final target = _program!;
        _error = null;
        if (_hasPicture) {
          _hasPicture = false;
          _transitionFrame = null;
          _transitionFrame = await _captureTransitionFrame();
          if (_closed) return;
          notifyListeners();
          if (!reducedMotion) await Future<void>.delayed(_fadeOutDuration);
        } else if (_switches > 0) {
          notifyListeners();
          // Coalesce quick key presses before opening the next media source.
          await Future<void>.delayed(const Duration(milliseconds: 55));
        } else {
          notifyListeners();
        }
        if (_closed) return;
        if (_program != target) continue;
        final now = DateTime.timestamp();
        if (!now.isBefore(target.endsAt)) {
          syncProgram();
          continue;
        }
        final superseded = Completer<bool>();
        _supersededTune = superseded;
        var timedOut = false;
        final ready = await Future.any([
          _openProgram(target, target.positionAt(now)).timeout(
            _tuneDeadline,
            onTimeout: () {
              timedOut = true;
              return false;
            },
          ),
          superseded.future,
        ]);
        if (identical(_supersededTune, superseded)) _supersededTune = null;
        if (_closed) return;
        if (_program != target) continue;
        if (ready) {
          final frame = await _captureTransitionFrame(settleSurface: true);
          if (_closed) return;
          if (_program != target) continue;
          _transitionFrame = frame;
          _hasPicture = true;
          _prepareNeighbors();
        } else {
          if (timedOut) {
            unawaited(_manager.cancelPreviewTune().catchError((_) {}));
          }
          _error = timedOut
              ? 'Channel took too long to load'
              : 'Channel unavailable';
        }
        return;
      }
    } finally {
      _tuning = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<Uint8List?> _captureTransitionFrame({
    bool settleSurface = false,
  }) async {
    final backend = _manager.backend;
    if (reducedMotion || backend is! Media3PlayerBackend) return null;
    // Media3's first-frame event can arrive before the hardware surface has
    // latched a frame for PixelCopy on Android TV.
    if (settleSurface) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_closed) return null;
    return backend.captureTransitionFrame().timeout(
      const Duration(milliseconds: 100),
      onTimeout: () => null,
    );
  }

  Future<bool> _openProgram(RetroProgram target, Duration position) async {
    try {
      await _manager.playItems(
        [target.item],
        startPosition: position,
        preview: true,
        allowPreviewSubtitleTranscoding: true,
      );
      if (!identical(_manager.queueService.currentItem, target.item) ||
          _manager.bringupState.phase != PlaybackBringupPhase.ready) {
        return false;
      }
      final backend = _manager.backend;
      return backend is! Media3PlayerBackend ||
          await backend.waitForFirstVideoFrame();
    } catch (_) {
      // Individual stream failures leave the dial available for another tune.
      return false;
    }
  }

  void _interruptTune() {
    _supersededTune?.complete(false);
    _supersededTune = null;
  }

  void _prepareNeighbors() {
    if (!PlatformDetection.isWeb) return;
    final now = DateTime.timestamp();
    _dial.update(now);
    final channels = _dial.channels;
    final index = channels.indexOf(_channel!);
    final ordered = [
      for (final distance in [_direction, -_direction, _direction * 2])
        channels[(index + distance) % channels.length],
    ].where((channel) => channel != _channel).toSet().toList();
    (Object, Duration) candidate(RetroChannel channel) {
      final program = channel.now;
      return (program.item, program.positionAt(now));
    }

    _manager.preparePreviewNeighbors([
      for (final neighbor in ordered.take(2)) candidate(neighbor),
    ], lookahead: ordered.length > 2 ? candidate(ordered[2]) : null);
  }

  void close() {
    _closed = true;
    _programEnd?.cancel();
    _catalogTimer?.cancel();
    _interruptTune();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

enum RetroTvPanel { hidden, banner, actions, details, browse }

class RetroTvOverlay extends StatefulWidget {
  const RetroTvOverlay({
    super.key,
    required this.session,
    required this.failed,
    required this.panel,
    required this.onTune,
    required this.client,
    required this.onAction,
    required this.onDismiss,
    required this.onCloseActions,
    required this.onExit,
  });

  final RetroTvSession session;
  final bool failed;
  final RetroTvPanel panel;
  final ValueChanged<RetroChannel> onTune;
  final MediaServerClient client;
  final ValueChanged<RetroTvAction> onAction;
  final VoidCallback onDismiss;
  final VoidCallback onCloseActions;
  final VoidCallback onExit;

  @override
  State<RetroTvOverlay> createState() => _RetroTvOverlayState();
}

class _RetroTvOverlayState extends State<RetroTvOverlay> {
  static const _cardHold = Duration(seconds: 4);
  Timer? _hideCard;

  String? get _error =>
      widget.session.error ??
      (widget.failed && !widget.session.busy ? 'Channel unavailable' : null);

  @override
  void initState() {
    super.initState();
    _updateCard();
  }

  @override
  void didUpdateWidget(covariant RetroTvOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCard();
  }

  void _updateCard() {
    if (widget.panel != RetroTvPanel.banner ||
        widget.session.busy ||
        _error != null) {
      _hideCard?.cancel();
      _hideCard = null;
    } else {
      _hideCard ??= Timer(_cardHold, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _hideCard?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final channel = session.channel;
    final program = session.program;
    final next = session.nextProgram;
    final error = _error;
    final Widget? bottom = program == null || next == null
        ? null
        : switch (widget.panel) {
            RetroTvPanel.hidden => null,
            RetroTvPanel.banner => RetroTvBanner(program: program, next: next),
            RetroTvPanel.browse ||
            RetroTvPanel.actions ||
            RetroTvPanel.details => null,
          };
    return Stack(
      fit: StackFit.expand,
      children: [
        _ChannelFade(
          waiting: session.busy,
          error: error,
          frame: session.transitionFrame,
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _RetroPanelReveal(
            alignment: Alignment.topLeft,
            child:
                widget.panel == RetroTvPanel.hidden ||
                    widget.panel == RetroTvPanel.browse ||
                    channel == null
                ? null
                : RetroTvChannelBanner(
                    key: ValueKey(channel),
                    channel: channel,
                  ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _RetroPanelReveal(
              alignment: Alignment.centerLeft,
              child: widget.panel == RetroTvPanel.browse && channel != null
                  ? RetroTvChannelBrowser(
                      channels: session.channels,
                      playing: channel,
                      onTune: widget.onTune,
                      onDismiss: widget.onCloseActions,
                      onExit: widget.onExit,
                    )
                  : null,
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: _RetroPanelReveal(
              alignment: Alignment.centerRight,
              child:
                  (widget.panel == RetroTvPanel.actions ||
                          widget.panel == RetroTvPanel.details) &&
                      program != null
                  ? RetroTvActionMenu(
                      key: const ValueKey('programme-actions'),
                      program: program,
                      onAction: widget.onAction,
                      onDismiss: widget.onCloseActions,
                      actionsEnabled: !session.busy && error == null,
                      previousAvailable: session.previousChannel != null,
                      details: widget.panel == RetroTvPanel.details
                          ? RetroTvDetails(
                              key: ValueKey(program),
                              item: program.item,
                              client: widget.client,
                            )
                          : null,
                    )
                  : null,
            ),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          right: 0,
          child: _RetroPanelReveal(
            alignment: Alignment.bottomLeft,
            child: bottom == null
                ? null
                : KeyedSubtree(
                    key: ValueKey(
                      widget.panel == RetroTvPanel.details
                          ? RetroTvPanel.actions
                          : widget.panel,
                    ),
                    child: Padding(
                      padding: widget.panel == RetroTvPanel.banner
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(
                              Tv26Style.inset,
                              0,
                              Tv26Style.inset,
                              Tv26Style.sectionGap,
                            ),
                      child: bottom,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Both ends of the screen share the same entrance, exit and outgoing focus rules.
class _RetroPanelReveal extends StatelessWidget {
  const _RetroPanelReveal({required this.alignment, this.child});
  final Alignment alignment;
  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.screen,
    switchInCurve: TvRevealTransition.curve,
    switchOutCurve: TvRevealTransition.curve,
    layoutBuilder: (current, previous) => Stack(
      alignment: alignment,
      children: [
        for (final old in previous)
          ExcludeFocus(
            child: ExcludeSemantics(child: IgnorePointer(child: old)),
          ),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) =>
        TvRevealTransition(animation: animation, child: child),
    child: child,
  );
}

class _ChannelFade extends StatefulWidget {
  const _ChannelFade({
    required this.waiting,
    required this.error,
    required this.frame,
  });

  final bool waiting;
  final String? error;
  final Uint8List? frame;

  @override
  State<_ChannelFade> createState() => _ChannelFadeState();
}

class _ChannelFadeState extends State<_ChannelFade>
    with SingleTickerProviderStateMixin {
  bool get _covered => widget.waiting || widget.error != null;

  late final _fade = AnimationController(
    vsync: this,
    duration: _fadeOutDuration,
    reverseDuration: AppMotion.screen,
    value: _covered ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFade();
  }

  @override
  void didUpdateWidget(_ChannelFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waiting != widget.waiting ||
        oldWidget.error != widget.error) {
      _syncFade();
    }
  }

  void _syncFade() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = _covered ? 1 : 0;
    } else if (_covered) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _fade,
        child: frame == null
            ? null
            : Image.memory(
                frame,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.low,
              ),
        builder: (context, frame) {
          final fade = TvRevealTransition.curve.transform(_fade.value);
          final blur = TvRevealTransition.blurSigma * fade;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Blur a still from the native surface while leaving playback on
              // the hardware plane. The veil also fades uncapturable sources.
              if (frame != null)
                Opacity(
                  opacity: fade == 1 ? 0 : (fade * 4).clamp(0.0, 1.0),
                  child: ImageFiltered(
                    enabled: blur > 0,
                    imageFilter: ImageFilter.blur(
                      sigmaX: blur,
                      sigmaY: blur,
                      tileMode: TileMode.clamp,
                    ),
                    child: frame,
                  ),
                ),
              ColoredBox(color: Tv26Style.canvas.withValues(alpha: fade)),
              if (widget.error case final error?)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error,
                        style: Tv26Style.text(22, color: Tv26Style.secondary),
                      ),
                      const SizedBox(height: Tv26Style.gap),
                      Text(
                        'OK Retry     ← Channels     ↑ ↓ Change channel',
                        style: Tv26Style.text(14, color: Tv26Style.secondary),
                      ),
                    ],
                  ),
                )
              else if (fade > .8)
                ExcludeSemantics(
                  excluding: !widget.waiting,
                  child: Opacity(
                    opacity: (fade - .8) * 5,
                    child: const Center(
                      child: LoadingThrobber(color: Tv26Style.foreground),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
