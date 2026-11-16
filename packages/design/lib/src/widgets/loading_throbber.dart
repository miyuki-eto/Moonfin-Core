import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared feedback for waits whose completion cannot be measured.
class LoadingThrobber extends StatefulWidget {
  const LoadingThrobber({
    super.key,
    this.size = defaultSize,
    this.color,
    this.semanticsLabel,
  });

  static const defaultSize = 96.0;

  final double size;
  final Color? color;
  final String? semanticsLabel;

  @override
  State<LoadingThrobber> createState() => _LoadingThrobberState();
}

class _LoadingThrobberState extends State<LoadingThrobber>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: CrtBeam.pulseDuration,
  );
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: widget.semanticsLabel ?? 'Loading',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        builder: (context, entrance, child) => RepaintBoundary(
          child: CustomPaint(
            size: Size(widget.size, widget.size / 2),
            painter: _LoadingBeam(
              phase: _pulse,
              color: color,
              reducedMotion: _reducedMotion,
              width: widget.size,
              entrance: _reducedMotion ? 1 : entrance,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingBeam extends CustomPainter {
  _LoadingBeam({
    required this.phase,
    required this.color,
    required this.reducedMotion,
    required this.width,
    required this.entrance,
  }) : super(repaint: phase);

  final Animation<double> phase;
  final Color color;
  final bool reducedMotion;
  final double width;
  final double entrance;

  @override
  void paint(Canvas canvas, Size size) {
    final expansion = reducedMotion ? .5 : CrtBeam.expansion(phase.value);
    if (size.isEmpty) return;
    final baseWidth = math.min(width, math.min(size.width, size.height * 2));
    final scale = math.min(1.0, baseWidth / LoadingThrobber.defaultSize);
    CrtBeam.paint(
      canvas,
      center: size.center(Offset.zero),
      width: CrtBeam.loadingWidth(baseWidth, expansion),
      height: scale * CrtBeam.loadingHeight(expansion),
      color: color.withValues(alpha: color.a * entrance),
    );
  }

  @override
  bool shouldRepaint(_LoadingBeam oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.width != width ||
      oldDelegate.entrance != entrance;
}

/// The soft phosphor beam shared by the loader and the TV shutter.
abstract final class CrtBeam {
  static const pulseDuration = Duration(seconds: 4);

  static double expansion(double phase) =>
      (1 - math.cos(2 * math.pi * phase)) / 2;

  static double loadingWidth(double size, double expansion) =>
      size * (.32 + .6 * expansion);

  static double loadingHeight(double expansion) => 10 + 5 * expansion;

  static void paint(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
    required Color color,
  }) {
    final glow = RadialGradient(
      colors: [
        color,
        color.withValues(alpha: color.a * .5),
        color.withValues(alpha: color.a * .12),
        color.withValues(alpha: 0),
      ],
      stops: const [0, .22, .52, 1],
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(width / 2, height / 2);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()..shader = glow.createShader(const Rect.fromLTRB(-1, -1, 1, 1)),
    );
    canvas.restore();
  }
}
