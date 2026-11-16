import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'tv_reveal_transition.dart';

/// One transition for Material routes on TV, including go, push and pop.
/// Fullscreen players retain their explicit zero-duration routes.
class TvPageTransitionsBuilder extends PageTransitionsBuilder {
  const TvPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.screen;

  @override
  Duration get reverseTransitionDuration => AppMotion.screen;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AnimatedBuilder(
    animation: Listenable.merge([animation, secondaryAnimation]),
    child: child,
    builder: (context, child) {
      final entering = TvRevealTransition.curve.transform(animation.value);
      final leaving = TvRevealTransition.curve.transform(
        secondaryAnimation.value,
      );
      return TvRevealTransition(
        animation: AlwaysStoppedAnimation(entering * (1 - leaving)),
        child: child!,
      );
    },
  );
}
