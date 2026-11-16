import 'package:flutter/widgets.dart';

/// Artwork and its fade are anchored to the top of the page. Scrolling reveals
/// the bottom of the picture, followed by black beneath the hero.
class TvDetailBackdrop extends StatelessWidget {
  final ScrollController scrollController;
  final double heroExtent;
  final Widget child;

  const TvDetailBackdrop({
    super.key,
    required this.scrollController,
    required this.heroExtent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF000000),
    child: AnimatedBuilder(
      animation: scrollController,
      child: child,
      builder: (context, artwork) {
        final offset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -offset),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xFFFFFFFF),
                Color(0xFFFFFFFF),
                Color(0x57FFFFFF),
                Color(0x29FFFFFF),
                Color(0x00FFFFFF),
              ],
              // Start shading before the synopsis and keep fading to black
              // beneath the actions, even when the source artwork is bright.
              stops: const [0, .38, .61, .86, 1],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, heroExtent)),
            child: artwork,
          ),
        );
      },
    ),
  );
}
