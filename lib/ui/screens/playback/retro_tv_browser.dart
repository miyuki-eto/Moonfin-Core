import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:moonfin_design/moonfin_design.dart';

import '../../../util/focus/key_event_utils.dart';
import '../../tv/tv26_button.dart';
import '../../widgets/scroll_edge_fade.dart';
import 'retro_tv_card.dart';
import 'retro_tv_dial.dart';

/// A schedule-only channel list. Enter or a deliberate dwell requests one tune.
class RetroTvChannelBrowser extends StatefulWidget {
  const RetroTvChannelBrowser({
    super.key,
    required this.channels,
    required this.playing,
    required this.onTune,
    required this.onDismiss,
    required this.onExit,
  });

  static const autoTuneDelay = Duration(seconds: 4);

  final List<RetroChannel> channels;
  final RetroChannel playing;
  final ValueChanged<RetroChannel> onTune;
  final VoidCallback onDismiss;
  final VoidCallback onExit;

  @override
  State<RetroTvChannelBrowser> createState() => _RetroTvChannelBrowserState();
}

class _RetroTvChannelBrowserState extends State<RetroTvChannelBrowser>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _rowHeight = 80.0;
  late int _selectedIndex = widget.channels.indexOf(widget.playing);
  RetroChannel get _selected =>
      widget.channels[_selectedIndex % widget.channels.length];
  late final _scroll = FixedExtentScrollController(
    initialItem: _selectedIndex,
    // Each opening centres the playing channel, never a previous guide offset.
    keepScrollOffset: false,
  );
  bool _manualScroll = false;
  final _nodes = <RetroChannel, FocusNode>{};
  bool _committed = false;
  late final _dwell =
      AnimationController(
        vsync: this,
        duration: RetroTvChannelBrowser.autoTuneDelay,
        // Accessibility motion preferences must not shorten the selection delay.
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _confirm(_selected);
      });

  FocusNode _node(RetroChannel channel) =>
      _nodes.putIfAbsent(channel, FocusNode.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(_selected).requestFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _dwell.reset();
  }

  void _highlight(RetroChannel channel) {
    if (_committed || !mounted || channel == _selected) return;
    final count = widget.channels.length;
    var step = widget.channels.indexOf(channel) - _selectedIndex % count;
    if (step > count / 2) step -= count;
    if (step < -count / 2) step += count;
    _move(step);
  }

  void _move(int step) {
    if (_committed) return;
    _manualScroll = false;
    _dwell.reset();
    setState(() => _selectedIndex += step);
    if (_selected != widget.playing) _dwell.forward();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpToItem(_selectedIndex);
    } else {
      _scroll.animateToItem(
        _selectedIndex,
        duration: AppMotion.normal,
        curve: AppMotion.ease,
      );
    }
    _focusSelected();
  }

  void _focusSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_committed) _node(_selected).requestFocus();
    });
  }

  void _confirm(RetroChannel channel) {
    if (!mounted || _committed || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _committed = true;
    _dwell.stop();
    widget.onTune(channel);
  }

  void _dismiss() {
    _dwell.reset();
    widget.onDismiss();
  }

  void _exit() {
    if (_committed) return;
    _committed = true;
    _dwell.reset();
    widget.onExit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dwell.dispose();
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) => handleBackKeyAction(event, _dismiss),
    onFocusChange: (focused) {
      if (!focused && mounted) _dwell.reset();
    },
    child: RetroTvSidePanel(
      width: 440,
      left: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tv26Style.inset,
          vertical: Tv26Style.sectionGap,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Channels',
              style: Tv26Style.text(21, weight: FontWeight.w700),
            ),
            const SizedBox(height: Tv26Style.gap / 2),
            Text(
              'Playing ${retroChannelLabel(widget.playing)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tv26Style.text(13, color: Tv26Style.secondary),
            ),
            const SizedBox(height: Tv26Style.detailHeaderGap),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle) {
                    _manualScroll = true;
                    _dwell.reset();
                  }
                  if (notification is ScrollEndNotification && _manualScroll) {
                    _manualScroll = false;
                    _dwell.reset();
                    setState(() => _selectedIndex = _scroll.selectedItem);
                    _focusSelected();
                  }
                  return false;
                },
                child: ScrollEdgeFade(
                  child: ListWheelScrollView.useDelegate(
                    controller: _scroll,
                    itemExtent:
                        _rowHeight * MediaQuery.textScalerOf(context).scale(1) +
                        Tv26Style.gap,
                    // Keep the list almost flat while retaining a centred,
                    // continuously looping wheel in both directions.
                    diameterRatio: 100,
                    perspective: .001,
                    physics: const FixedExtentScrollPhysics(),
                    childDelegate: ListWheelChildLoopingListDelegate(
                      children: widget.channels.map((channel) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Tv26Style.gap / 2,
                          ),
                          child: Tv26Button(
                            label:
                                '${retroChannelLabel(channel)}. Now ${channel.now.item.seriesName ?? channel.now.item.name}',
                            height:
                                _rowHeight *
                                MediaQuery.textScalerOf(context).scale(1),
                            cornerRadius: Tv26Style.radius,
                            iconOnly: true,
                            transparent: true,
                            leadingBuilder: (foreground) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Tv26Style.menuRowHorizontalInset,
                                ),
                                child: RetroTvProgramListing(
                                  program: channel.now,
                                  label:
                                      '${channel == widget.playing ? '▶  ' : ''}${retroChannelLabel(channel)}',
                                  compact: true,
                                  current: true,
                                  foregroundColor: foreground,
                                ),
                              ),
                            ),
                            focusNode: _node(channel),
                            onPressed: () => _confirm(channel),
                            onUp: () => _move(-1),
                            onDown: () => _move(1),
                            onLeft: _exit,
                            onRight: _dismiss,
                            onFocusChange: (focused) {
                              if (focused) _highlight(channel);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Tv26Style.gap),
            AnimatedBuilder(
              animation: _dwell,
              builder: (context, _) => Text(
                _selected == widget.playing
                    ? 'Watching this channel'
                    : _dwell.isAnimating
                    ? 'Switching in ${(RetroTvChannelBrowser.autoTuneDelay.inMilliseconds * (1 - _dwell.value) / 1000).ceil()}s'
                    : 'OK to watch',
                style: Tv26Style.text(13, color: Tv26Style.detailHeroSecondary),
              ),
            ),
            const SizedBox(height: Tv26Style.gap),
            Text(
              '↑ ↓ Browse   OK Watch   ← Media   Back Close',
              style: Tv26Style.text(12, color: Tv26Style.secondary),
            ),
          ],
        ),
      ),
    ),
  );
}
