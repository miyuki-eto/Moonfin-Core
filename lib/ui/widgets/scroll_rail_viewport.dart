import 'package:flutter/widgets.dart';

import 'scroll_edge_fade.dart';

/// Shared paint bounds for horizontal rails, independent of their focus model.
/// Insets let a row bleed into a section's outer gutters without moving cards.
class ScrollRailViewport extends StatelessWidget {
  final double height;
  final EdgeInsets padding;
  final EdgeInsets viewportInsets;
  final double paintOutset;
  final Widget Function(BuildContext context, EdgeInsetsGeometry padding)
  builder;

  const ScrollRailViewport({
    super.key,
    required this.height,
    required this.builder,
    this.padding = EdgeInsets.zero,
    this.viewportInsets = EdgeInsets.zero,
    this.paintOutset = 0,
  });

  static double horizontalPaintOutset(double paintOutset) =>
      paintOutset == 0 ? 0 : paintOutset + ScrollEdgeFade.horizontalDistance;

  @override
  Widget build(BuildContext context) {
    assert(viewportInsets.vertical == 0);
    final horizontalOutset = horizontalPaintOutset(paintOutset);
    final contentPadding = EdgeInsets.fromLTRB(
      padding.left + viewportInsets.left,
      padding.top,
      padding.right + viewportInsets.right,
      padding.bottom,
    );
    final leadingGutter = paintOutset > 0 && contentPadding.left > paintOutset;
    Widget viewport(EdgeInsetsGeometry padding) => ScrollEdgeFade(
      axis: Axis.horizontal,
      startInset: leadingGutter ? horizontalOutset : 0,
      startDistance: leadingGutter
          ? (contentPadding.left - paintOutset).clamp(
              0.0,
              ScrollEdgeFade.horizontalDistance,
            )
          : null,
      endInset: horizontalOutset,
      child: builder(context, padding),
    );
    return SizedBox(
      height: height,
      child: paintOutset == 0 && viewportInsets.horizontal == 0
          ? viewport(contentPadding)
          : LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth +
                    viewportInsets.horizontal +
                    horizontalOutset * 2;
                final paintHeight = height + paintOutset * 2;
                return OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: width,
                  maxWidth: width,
                  minHeight: paintHeight,
                  maxHeight: paintHeight,
                  child: Transform.translate(
                    offset: Offset(
                      -horizontalOutset - viewportInsets.left,
                      -paintOutset,
                    ),
                    child: SizedBox(
                      width: width,
                      height: paintHeight,
                      child: viewport(
                        contentPadding.add(
                          EdgeInsets.symmetric(
                            horizontal: horizontalOutset,
                            vertical: paintOutset,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
