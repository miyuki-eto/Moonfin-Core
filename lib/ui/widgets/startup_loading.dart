import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../platform/web_startup_splash.dart';

void finishWebStartupSplashAfterFrame(BuildContext context) {
  if (!webStartupSplashVisible) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted && ModalRoute.of(context)?.isCurrent != false) {
      finishWebStartupSplash();
    }
  });
}

/// Keeps the Flutter loading mark aligned with the pre-Flutter web splash.
class StartupLoading extends StatefulWidget {
  const StartupLoading({super.key});

  @override
  State<StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<StartupLoading> {
  @override
  Widget build(BuildContext context) {
    // The browser glow already owns this wait, including its animation phase.
    if (webStartupSplashVisible) {
      return const ColoredBox(color: Colors.black);
    }
    final view = View.of(context);
    final viewportWidth = view.physicalSize.width / view.devicePixelRatio;
    final canvasWidth = MediaQuery.sizeOf(context).width;
    final scale = canvasWidth > 0 && viewportWidth > 0
        ? viewportWidth / canvasWidth
        : 1.0;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: LoadingThrobber(
          key: const ValueKey('startup-throbber'),
          size: LoadingThrobber.defaultSize / scale,
          color: Colors.white,
        ),
      ),
    );
  }
}
