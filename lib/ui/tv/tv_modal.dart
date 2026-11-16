import 'dart:ui';

import 'package:flutter/material.dart';

import '../../util/focus/input_mode_tracker.dart';

import 'package:moonfin_design/moonfin_design.dart';

import '../../util/focus/key_event_utils.dart';
import 'tv_reveal_transition.dart';

/// Shared entrance for TV dialogs. The scrim belongs to the route; only the
/// panel content scales, so opening a menu never scales the page behind it.
Widget tvModalTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child, {
  bool blurBackground = true,
}) {
  if (!blurBackground) {
    return TvRevealTransition(animation: animation, child: child);
  }
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) => BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: MediaQuery.disableAnimationsOf(context)
            ? 0
            : 6 * animation.value,
        sigmaY: MediaQuery.disableAnimationsOf(context)
            ? 0
            : 6 * animation.value,
      ),
      child: TvRevealTransition(animation: animation, child: child!),
    ),
  );
}

class TvModalPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;
  final double cornerRadius;

  const TvModalPanel({
    super.key,
    required this.child,
    this.padding = Tv26Style.modalContentPadding,
    this.constraints,
    this.cornerRadius = Tv26Style.panelRadius,
  });

  const TvModalPanel.menu({super.key, required this.child, this.constraints})
    : padding = Tv26Style.modalMenuPadding,
      cornerRadius = Tv26Style.panelRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(cornerRadius),
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: Tv26Style.panelBlur,
        sigmaY: Tv26Style.panelBlur,
      ),
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Tv26Style.modalSurface,
            borderRadius: BorderRadius.circular(cornerRadius),
            border: Tv26Style.surfaceBorder,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

/// One remote/pointer row used by track selectors and action menus. Selection
/// is the checkmark; focus is a white surface. No focus scaling is applied.
class TvMenuRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool dimmed;
  final int? labelMaxLines;
  final int subtitleMaxLines;
  final List<String> badges;
  final Widget? trailing;

  /// Decorative glyphs follow focus contrast; artwork keeps its own colours.
  final bool tintTrailing;
  final VoidCallback onPressed;

  const TvMenuRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.dimmed = false,
    this.labelMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.badges = const [],
    this.trailing,
    this.tintTrailing = true,
  });

  @override
  State<TvMenuRow> createState() => _TvMenuRowState();
}

class _TvMenuRowState extends State<TvMenuRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active =
        _focused || (_hovered && InputModeTracker.pointerIsLive(context));
    final color = active ? Tv26Style.canvas : Tv26Style.foreground;
    return Semantics(
      button: true,
      focused: _focused,
      selected: widget.selected,
      excludeSemantics: true,
      label: [
        widget.label,
        if (widget.subtitle?.isNotEmpty ?? false) widget.subtitle!,
      ].join(', '),
      onTap: widget.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Scrollable.ensureVisible(
                  context,
                  alignment: .5,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppMotion.fast,
                );
              }
            });
          }
        },
        onKeyEvent: dpadKeyHandler(onSelect: widget.onPressed),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.fast,
              curve: AppMotion.ease,
              padding: const EdgeInsets.symmetric(
                horizontal: Tv26Style.menuRowHorizontalInset,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: active ? Tv26Style.foreground : Colors.transparent,
                borderRadius: BorderRadius.circular(Tv26Style.rowRadius),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(
                      widget.selected ? Icons.check_rounded : widget.icon,
                      size: 22,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: Tv26Style.gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          maxLines: widget.labelMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: Tv26Style.text(
                            18,
                            color: color.withValues(
                              alpha: widget.dimmed && !active ? .6 : 1,
                            ),
                            weight: FontWeight.w600,
                          ),
                        ),
                        if (widget.subtitle?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            maxLines: widget.subtitleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: Tv26Style.text(
                              14,
                              color: active
                                  ? color.withValues(alpha: .7)
                                  : Tv26Style.secondary,
                            ),
                          ),
                        ],
                        if (widget.badges.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.badges.join(' · '),
                            style: Tv26Style.text(
                              12,
                              color: active
                                  ? color.withValues(alpha: .7)
                                  : Tv26Style.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: Tv26Style.gap),
                    ExcludeFocus(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: widget.tintTrailing
                              ? ColorFiltered(
                                  colorFilter: ColorFilter.mode(
                                    color,
                                    BlendMode.srcIn,
                                  ),
                                  child: widget.trailing!,
                                )
                              : widget.trailing!,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
