import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../tv/tv26_button.dart';
import 'retro_tv_card.dart';
import 'retro_tv_dial.dart';

/// Programme actions open deliberately at the right edge of the playing video.
class RetroTvActionMenu extends StatefulWidget {
  const RetroTvActionMenu({
    super.key,
    required this.program,
    required this.onAction,
    required this.onDismiss,
    this.actionsEnabled = true,
    this.previousAvailable = false,
    this.details,
  });

  final RetroProgram program;
  final ValueChanged<RetroTvAction> onAction;
  final VoidCallback onDismiss;
  final bool actionsEnabled;
  final bool previousAvailable;
  final Widget? details;

  @override
  State<RetroTvActionMenu> createState() => _RetroTvActionMenuState();
}

class _RetroTvActionMenuState extends State<RetroTvActionMenu> {
  static const _menuWidth = 360.0;
  static const _actions = [
    (RetroTvAction.details, 'View Details', Icons.info_outline_rounded),
    (RetroTvAction.watch, 'Watch in Media', Icons.play_arrow_rounded),
    (
      RetroTvAction.startOver,
      'Watch from beginning',
      Icons.restart_alt_rounded,
    ),
    (RetroTvAction.previous, 'Previous Channel', Icons.undo_rounded),
  ];
  final _nodes = List.generate(_actions.length, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  bool _enabled(RetroTvAction action) => switch (action) {
    RetroTvAction.details => true,
    RetroTvAction.previous => widget.previousAvailable,
    RetroTvAction.watch || RetroTvAction.startOver => widget.actionsEnabled,
  };

  @override
  Widget build(BuildContext context) => RetroTvSidePanel(
    width: widget.details == null ? _menuWidth : 960,
    child: Row(
      children: [
        if (widget.details != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: Tv26Style.inset,
                right: Tv26Style.gap,
              ),
              child: SizedBox(
                height: 400 * MediaQuery.textScalerOf(context).scale(1),
                child: widget.details!,
              ),
            ),
          ),
        SizedBox(
          key: const ValueKey('retro-actions'),
          width: _menuWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tv26Style.inset,
              vertical: Tv26Style.sectionGap,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RetroTvProgramListing(
                  program: widget.program,
                  label: 'NOW',
                  current: true,
                  compact: true,
                ),
                const SizedBox(height: Tv26Style.detailHeaderGap),
                for (var index = 0; index < _actions.length; index++) ...[
                  if (index > 0) const SizedBox(height: Tv26Style.gap),
                  Opacity(
                    opacity: _enabled(_actions[index].$1) ? 1 : .45,
                    child: Tv26Button(
                      label: index == 0 && widget.details != null
                          ? 'Hide Details'
                          : _actions[index].$2,
                      icon: _actions[index].$3,
                      height: 48,
                      fontSize: 17,
                      cornerRadius: Tv26Style.radius,
                      horizontalPadding: Tv26Style.menuRowHorizontalInset,
                      contentAlignment: MainAxisAlignment.start,
                      focusNode: _nodes[index],
                      onPressed: () {
                        if (_enabled(_actions[index].$1)) {
                          widget.onAction(_actions[index].$1);
                        }
                      },
                      onUp: () =>
                          _nodes[(index - 1).clamp(0, _nodes.length - 1)]
                              .requestFocus(),
                      onDown: () =>
                          _nodes[(index + 1).clamp(0, _nodes.length - 1)]
                              .requestFocus(),
                      onLeft: widget.onDismiss,
                      onRight: () {},
                    ),
                  ),
                ],
                const SizedBox(height: Tv26Style.detailHeaderGap),
                Text(
                  '↑ ↓ Choose   OK Select   Back Close',
                  maxLines: 1,
                  style: Tv26Style.text(12, color: Tv26Style.secondary),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
