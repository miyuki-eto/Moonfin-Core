import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// Opaque navigation stays readable independently of the page's artwork.
class Tv26Sidebar extends StatelessWidget {
  final Widget child;

  const Tv26Sidebar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Tv26Style.sidebarWidth,
    child: Padding(
      padding: Tv26Style.sidebarMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tv26Style.panelRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Tv26Style.sidebarSurface,
            borderRadius: BorderRadius.circular(Tv26Style.panelRadius),
            border: Tv26Style.surfaceBorder,
          ),
          child: child,
        ),
      ),
    ),
  );
}
