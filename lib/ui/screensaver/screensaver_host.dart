import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'screensaver_controller.dart';
import 'screensaver_view.dart';

import 'package:moonfin_design/moonfin_design.dart';

import '../tv/tv_reveal_transition.dart';

class ScreensaverHost extends StatelessWidget {
  const ScreensaverHost({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GetIt.instance<ScreensaverController>();
    return ValueListenableBuilder<bool>(
      valueListenable: controller.visible,
      builder: (context, visible, _) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.slow,
            transitionBuilder: (child, animation) =>
                TvRevealTransition(animation: animation, child: child),
            child: visible
                ? Listener(
                    key: const ValueKey('screensaver'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => controller.dismiss(),
                    child: const ScreensaverView(),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
