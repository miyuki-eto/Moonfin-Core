import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../util/focus/dpad_keys.dart';
import '../../../../util/focus/key_event_utils.dart';
import '../../../tv/tv26_button.dart';

/// Keeps remote focus in Flutter rather than the provider's embedded player.
class TvTrailerControls extends StatefulWidget {
  final bool paused;
  final VoidCallback onTogglePause;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback onBack;

  const TvTrailerControls({
    super.key,
    required this.paused,
    required this.onTogglePause,
    required this.onBack,
    this.onSeek,
  });

  @override
  State<TvTrailerControls> createState() => _TvTrailerControlsState();
}

class _TvTrailerControlsState extends State<TvTrailerControls> {
  final _root = FocusNode(debugLabel: 'trailer transport');
  final _back = FocusNode(debugLabel: 'trailer back');
  final _rewind = FocusNode(debugLabel: 'trailer rewind');
  final _play = FocusNode(debugLabel: 'trailer play pause');
  final _forward = FocusNode(debugLabel: 'trailer forward');
  Timer? _hideTimer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _armHide();
  }

  @override
  void didUpdateWidget(covariant TvTrailerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused) {
      _hideTimer?.cancel();
      _visible = true;
      if (_root.hasPrimaryFocus) _focusPlayAfterReveal();
    } else {
      _armHide();
    }
  }

  void _focusPlayAfterReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) _play.requestFocus();
    });
  }

  void _armHide() {
    _hideTimer?.cancel();
    if (widget.paused) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _root.requestFocus();
      setState(() => _visible = false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final back = handleBackKeyAction(event, widget.onBack);
    if (back != KeyEventResult.ignored) return back;
    if (!event.isActionable) return KeyEventResult.ignored;
    _armHide();
    final key = event.logicalKey;
    if (!_visible &&
        (key.isSelectKey ||
            key.isUpKey ||
            key.isDownKey ||
            key.isLeftKey ||
            key.isRightKey)) {
      setState(() => _visible = true);
      _focusPlayAfterReveal();
      if (key.isSelectKey) {
        return handleOneShotSelect(event, widget.onTogglePause);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      widget.onTogglePause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final node in [_root, _back, _rewind, _play, _forward]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Focus(
      focusNode: _root,
      onKeyEvent: _onKey,
      child: ExcludeFocus(
        excluding: !_visible,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.fast,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x66000000),
                            Colors.transparent,
                            Color(0xB3000000),
                          ],
                          stops: [0, .45, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: Tv26Style.inset,
                  left: Tv26Style.inset,
                  child: Tv26Button(
                    label: l10n.back,
                    icon: Icons.chevron_left,
                    focusNode: _back,
                    onPressed: widget.onBack,
                    onFocusChange: (_) => _armHide(),
                    onDown: _play.requestFocus,
                    onUp: () {},
                    onLeft: () {},
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: Tv26Style.inset,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.onSeek != null) ...[
                        Tv26Button(
                          label: l10n.playerTooltipSeekBack,
                          icon: Icons.replay_10,
                          focusNode: _rewind,
                          iconOnly: true,
                          width: 48,
                          onPressed: () {
                            _armHide();
                            widget.onSeek!(const Duration(seconds: -10));
                          },
                          onLeft: () {},
                          onRight: _play.requestFocus,
                          onUp: _back.requestFocus,
                          onDown: () {},
                          onFocusChange: (_) => _armHide(),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Tv26Button(
                        label: widget.paused ? l10n.play : l10n.pause,
                        icon: widget.paused ? Icons.play_arrow : Icons.pause,
                        focusNode: _play,
                        autofocus: true,
                        onPressed: widget.onTogglePause,
                        onLeft: widget.onSeek == null
                            ? () {}
                            : _rewind.requestFocus,
                        onRight: widget.onSeek == null
                            ? () {}
                            : _forward.requestFocus,
                        onUp: _back.requestFocus,
                        onDown: () {},
                        onFocusChange: (_) => _armHide(),
                      ),
                      if (widget.onSeek != null) ...[
                        const SizedBox(width: 16),
                        Tv26Button(
                          label: l10n.playerTooltipSeekForward,
                          icon: Icons.forward_10,
                          focusNode: _forward,
                          iconOnly: true,
                          width: 48,
                          onPressed: () {
                            _armHide();
                            widget.onSeek!(const Duration(seconds: 10));
                          },
                          onLeft: _play.requestFocus,
                          onRight: () {},
                          onUp: _back.requestFocus,
                          onDown: () {},
                          onFocusChange: (_) => _armHide(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
