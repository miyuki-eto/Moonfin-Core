import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// Edge hints follow the nearest viewport's actual extent, including resize
/// and programmatic D-pad scrolling. Only the scroll content is masked, so
/// artwork behind the viewport remains visible through its edges.
class ScrollEdgeFade extends StatefulWidget {
  static const horizontalDistance = Tv26Style.railFadeDistance;
  static const verticalDistance = 80.0;
  final Widget child;
  final Axis axis;
  final double? distance;

  /// A narrower leading gutter can finish fading before a focus frame.
  final double? startDistance;

  /// Keep scrolled content clear of a fixed control before the fade begins.
  /// At the start of the scroll this inset is opaque, like the rest of the page.
  final double startInset;
  final double endInset;

  /// Whether the trailing fade appears before the user scrolls.
  final bool fadeAfterAtStart;

  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
    this.distance,
    this.startDistance,
    this.startInset = 0,
    this.endInset = 0,
    this.fadeAfterAtStart = true,
  });

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _before = false;
  bool _after = false;
  AxisDirection _direction = AxisDirection.down;
  (bool, bool, AxisDirection)? _pendingEdges;
  bool _updateScheduled = false;

  void _measure(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != widget.axis) return;
    final before = metrics.extentBefore > 2;
    final after = metrics.extentAfter > 2;
    _pendingEdges = (before, after, metrics.axisDirection);
    if (_updateScheduled) return;
    if (_pendingEdges == (_before, _after, _direction)) {
      _pendingEdges = null;
      return;
    }
    // Viewports can emit scroll activity during layout when lazy extents change.
    // Coalesce those measurements and rebuild the fade after layout finishes.
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      final edges = _pendingEdges;
      _pendingEdges = null;
      if (!mounted || edges == null || edges == (_before, _after, _direction)) {
        return;
      }
      setState(() {
        _before = edges.$1;
        _after = edges.$2;
        _direction = edges.$3;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final reverse =
        _direction == AxisDirection.left || _direction == AxisDirection.up;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final fadeAfter = _after && (_before || widget.fadeAfterAtStart);
    final start = (reverse ? fadeAfter : _before) ? 1.0 : 0.0;
    final end = (reverse ? _before : fadeAfter) ? 1.0 : 0.0;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _measure(notification.metrics, notification.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _measure(notification.metrics, notification.depth);
          return false;
        },
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: Offset(start, end)),
          duration: reducedMotion ? Duration.zero : AppMotion.slow,
          curve: AppMotion.ease,
          child: widget.child,
          builder: (context, edges, child) => ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final extent = horizontal ? bounds.width : bounds.height;
                final distance =
                    widget.distance ??
                    (horizontal
                        ? ScrollEdgeFade.horizontalDistance
                        : ScrollEdgeFade.verticalDistance);
                final inset = extent <= 0
                    ? 0.0
                    : (widget.startInset / extent).clamp(0.0, .25);
                final endInset = extent <= 0
                    ? 0.0
                    : (widget.endInset / extent).clamp(0.0, .25);
                final fraction = extent <= 0
                    ? 0.0
                    : (distance / extent).clamp(
                        0.0,
                        .5 - (inset > endInset ? inset : endInset),
                      );
                final startFraction = extent <= 0
                    ? 0.0
                    : ((widget.startDistance ?? distance) / extent).clamp(
                        0.0,
                        .5 - (inset > endInset ? inset : endInset),
                      );
                Color alpha(double value) =>
                    Colors.white.withValues(alpha: value);
                return LinearGradient(
                  begin: horizontal
                      ? Alignment.centerLeft
                      : Alignment.topCenter,
                  end: horizontal
                      ? Alignment.centerRight
                      : Alignment.bottomCenter,
                  colors: [
                    alpha(1 - edges.dx),
                    alpha(1 - edges.dx),
                    alpha(1 - .75 * edges.dx),
                    alpha(1 - .35 * edges.dx),
                    alpha(1 - .08 * edges.dx),
                    Colors.white,
                    Colors.white,
                    alpha(1 - .08 * edges.dy),
                    alpha(1 - .35 * edges.dy),
                    alpha(1 - .75 * edges.dy),
                    alpha(1 - edges.dy),
                    alpha(1 - edges.dy),
                  ],
                  stops: [
                    0,
                    inset,
                    inset + startFraction * .22,
                    inset + startFraction * .48,
                    inset + startFraction * .78,
                    inset + startFraction,
                    1 - endInset - fraction,
                    1 - endInset - fraction * .78,
                    1 - endInset - fraction * .48,
                    1 - endInset - fraction * .22,
                    1 - endInset,
                    1,
                  ],
                ).createShader(bounds);
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
