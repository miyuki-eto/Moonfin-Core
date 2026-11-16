import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// Artwork and detail routes share a soft reveal, with no focus zoom.
class TvRevealTransition extends StatelessWidget {
  static const duration = AppMotion.slow;
  static const curve = Curves.easeInOutCubic;
  static const blurSigma = 10.0;
  final Animation<double> animation;
  final Widget child;

  const TvRevealTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final progress = reduced ? const AlwaysStoppedAnimation(1.0) : animation;
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) {
          final remaining = 1 - progress.value.clamp(0.0, 1.0);
          return ImageFiltered(
            enabled: remaining > 0,
            imageFilter: ImageFilter.blur(
              sigmaX: blurSigma * remaining,
              sigmaY: blurSigma * remaining,
              tileMode: TileMode.clamp,
            ),
            child: Transform.scale(scale: 1 + .012 * remaining, child: child),
          );
        },
      ),
    );
  }
}

/// Starts when real content mounts, even if its route finished animating
/// while waiting for the server. Rebuilds preserve focus and animation progress.
class TvContentReveal extends StatefulWidget {
  final Widget child;
  final bool ready;

  /// Hardware video planes cannot be blurred or faded as Flutter textures.
  final bool nativeSurface;

  const TvContentReveal({
    super.key,
    required this.child,
    this.ready = true,
    this.nativeSurface = false,
  });

  @override
  State<TvContentReveal> createState() => _TvContentRevealState();
}

class _TvContentRevealState extends State<TvContentReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.screen,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: TvRevealTransition.curve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startWhenReady();
  }

  @override
  void didUpdateWidget(TvContentReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _startWhenReady();
  }

  void _startWhenReady() {
    if (!widget.ready || _controller.value > 0 || _controller.isAnimating) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    // Let the loaded composition mount before spending its entrance animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.ready && !_controller.isAnimating) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nativeSurface) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: FadeTransition(
              opacity: ReverseAnimation(_progress),
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ],
      );
    }
    return TvRevealTransition(animation: _progress, child: widget.child);
  }
}
