import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../util/focus/key_event_utils.dart';
import '../../util/focus/input_mode_tracker.dart';

/// TV pills use their fill for focus, without Moonfin's accent ring or zoom.
class Tv26Button extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? skipTraversal;
  final bool primary;
  final bool iconOnly;
  final bool selected;
  final bool transparent;
  final double? width;
  final double height;
  final double iconSize;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? foregroundColor;
  final double horizontalPadding;
  final Widget? leading;
  final Widget Function(Color foreground)? leadingBuilder;
  final MainAxisAlignment contentAlignment;
  final double? cornerRadius;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final ValueChanged<bool>? onFocusChange;
  final ValueChanged<bool>? onHoverChange;

  /// Navigation owned by a compound control, such as a wrapped studio list.
  final FocusOnKeyEventCallback? onKeyEvent;

  const Tv26Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.skipTraversal,
    this.primary = false,
    this.iconOnly = false,
    this.selected = false,
    this.transparent = false,
    this.width,
    this.height = 40,
    this.iconSize = 20,
    this.fontSize = 18,
    this.fontWeight = FontWeight.w600,
    this.foregroundColor,
    this.horizontalPadding = 14,
    this.leading,
    this.leadingBuilder,
    this.contentAlignment = MainAxisAlignment.center,
    this.cornerRadius,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onFocusChange,
    this.onHoverChange,
    this.onKeyEvent,
  });

  @override
  State<Tv26Button> createState() => _Tv26ButtonState();
}

class _Tv26ButtonState extends State<Tv26Button> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted =
        _focused || (_hovered && InputModeTracker.pointerIsLive(context));
    final light = highlighted || widget.selected;
    final fg = light
        ? Colors.black
        : widget.foregroundColor ?? Tv26Style.foreground;
    return Semantics(
      label: widget.label,
      focused: _focused,
      button: true,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        skipTraversal: widget.skipTraversal,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
        },
        onKeyEvent:
            widget.onKeyEvent ??
            dpadKeyHandler(
              onSelect: widget.onPressed,
              onUp: widget.onUp,
              onDown: widget.onDown,
              onLeft: widget.onLeft,
              onRight: widget.onRight,
            ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _hovered = true);
            widget.onHoverChange?.call(true);
          },
          onExit: (_) {
            setState(() => _hovered = false);
            widget.onHoverChange?.call(false);
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.fast,
              curve: AppMotion.ease,
              height: widget.height,
              width: widget.width,
              padding: EdgeInsets.symmetric(
                horizontal: widget.iconOnly ? 0 : widget.horizontalPadding,
              ),
              decoration: BoxDecoration(
                color: light
                    ? Tv26Style.foreground
                    : widget.transparent
                    ? Colors.transparent
                    : Tv26Style.buttonSurface,
                borderRadius: BorderRadius.circular(
                  widget.cornerRadius ?? widget.height / 2,
                ),
                border: Tv26Style.surfaceBorder,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: widget.contentAlignment,
                children: [
                  if (widget.leadingBuilder != null)
                    widget.leadingBuilder!(fg)
                  else if (widget.leading != null)
                    widget.leading!
                  else if (widget.icon != null)
                    Icon(widget.icon, size: widget.iconSize, color: fg),
                  if (!widget.iconOnly) ...[
                    if (widget.icon != null ||
                        widget.leading != null ||
                        widget.leadingBuilder != null)
                      const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tv26Style.text(
                          widget.fontSize,
                          color: fg,
                          weight: widget.fontWeight,
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
