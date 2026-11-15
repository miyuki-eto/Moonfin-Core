import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// A shared pane for season, person and search tabs. Its inner radius follows
/// the same inset as the buttons, including controls with a custom height.
class TvSegmentedSurface extends StatelessWidget {
  final double height;
  final Widget child;

  const TvSegmentedSurface({
    super.key,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Tv26Style.surface,
          border: Tv26Style.surfaceBorder,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tv26Style.segmentInset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              radius - Tv26Style.segmentInset,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
