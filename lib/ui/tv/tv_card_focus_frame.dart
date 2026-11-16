import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// The ring is 3px wide with a 3px gap; all three contours share a center.
class TvCardFocusFrame extends StatelessWidget {
  final bool focused;
  final Widget child;
  final BorderRadius? borderRadius;

  const TvCardFocusFrame({
    super.key,
    required this.focused,
    required this.child,
    this.borderRadius,
  });

  BorderRadius get _radius =>
      borderRadius ?? BorderRadius.circular(Tv26Style.cardRadius);

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(borderRadius: _radius, child: child),
      Positioned(
        top: -Tv26Style.focusOutset,
        bottom: -Tv26Style.focusOutset,
        left: -Tv26Style.focusOutset,
        right: -Tv26Style.focusOutset,
        child: IgnorePointer(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.fast,
            curve: AppMotion.ease,
            decoration: BoxDecoration(
              borderRadius:
                  _radius + BorderRadius.circular(Tv26Style.focusOutset),
              border: Border.all(
                width: Tv26Style.focusWidth,
                color: focused ? Tv26Style.foreground : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
