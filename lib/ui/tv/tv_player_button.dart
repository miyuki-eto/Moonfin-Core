import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

class TvPlayerButton extends StatefulWidget {
  const TvPlayerButton({
    super.key,
    required this.extent,
    required this.child,
    this.focusNode,
    this.tooltip,
    this.onPressed,
    this.onRightBoundary,
  });

  final FocusNode? focusNode;
  final double extent;
  final String? tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onRightBoundary;
  final Widget child;

  @override
  State<TvPlayerButton> createState() => TvPlayerButtonState();
}

class TvPlayerButtonState extends State<TvPlayerButton> {
  late FocusNode _effectiveNode;
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _effectiveNode = widget.focusNode!;
    } else {
      _effectiveNode = FocusNode();
      _ownsNode = true;
    }
    _effectiveNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TvPlayerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newNode = widget.focusNode;
    final oldNode = oldWidget.focusNode;
    if (newNode != oldNode) {
      _effectiveNode.removeListener(_onFocusChange);
      if (_ownsNode) {
        _effectiveNode.dispose();
        _ownsNode = false;
      }
      if (newNode != null) {
        _effectiveNode = newNode;
      } else {
        _effectiveNode = FocusNode();
        _ownsNode = true;
      }
      _effectiveNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_onFocusChange);
    if (_ownsNode) {
      _effectiveNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) {
      return;
    }
    final hasFocus = _effectiveNode.hasFocus;
    if (_focused != hasFocus) {
      setState(() => _focused = hasFocus);
    }

    if (hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_effectiveNode.hasFocus) {
          return;
        }
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.fast,
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tooltipText = widget.tooltip;
    final hasTooltip = tooltipText != null && tooltipText.isNotEmpty;
    final focusWidget = Focus(
      focusNode: _effectiveNode,
      canRequestFocus: widget.onPressed != null,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final moved = FocusScope.of(context).previousFocus();
            return moved ? KeyEventResult.handled : KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (widget.onRightBoundary != null) {
              widget.onRightBoundary!();
              return KeyEventResult.handled;
            }
            final moved = FocusScope.of(context).nextFocus();
            return moved ? KeyEventResult.handled : KeyEventResult.ignored;
          }
        }
        if (widget.onPressed != null &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.fast,
        width: widget.extent,
        height: widget.extent,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _focused
              ? Tv26Style.foreground
              : Tv26Style.surface.withValues(alpha: .72),
          border: _focused
              ? Border.fromBorderSide(
                  ThemeRegistry.active.borders.focusBorder.copyWith(
                    color: Colors.white,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Center(
          child: _focused
              ? ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Tv26Style.canvas,
                    BlendMode.srcIn,
                  ),
                  child: widget.child,
                )
              : widget.child,
        ),
      ),
    );
    final button = widget.onPressed != null
        ? GestureDetector(onTap: widget.onPressed, child: focusWidget)
        : focusWidget;

    if (!_focused || !hasTooltip) {
      return Semantics(
        label: tooltipText,
        focused: _focused,
        excludeSemantics: true,
        button: true,
        onTap: widget.onPressed,
        child: button,
      );
    }

    return Semantics(
      label: tooltipText,
      focused: _focused,
      excludeSemantics: true,
      button: true,
      onTap: widget.onPressed,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          button,
          Positioned(
            bottom: widget.extent + 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: AppRadius.circular(8),
                  border: Border.fromBorderSide(
                    ThemeRegistry.active.borders.focusBorder.copyWith(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    tooltipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.fontSizeXs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
