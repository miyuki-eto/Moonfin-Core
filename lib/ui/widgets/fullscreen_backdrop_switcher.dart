import 'offline_aware_image.dart';

import 'package:flutter/widgets.dart';

import '../tv/tv_reveal_transition.dart';

class FullscreenBackdropSwitcher extends StatefulWidget {
  final String? imageUrl;
  final Duration duration;
  final Alignment alignment;
  final Duration fadeInDuration;
  final Widget Function(String imageUrl)? imageBuilder;
  final bool animateInitialImage;
  final bool softenTransition;

  /// Reports a decoded frame or an image failure, so an owning page can reveal
  /// its complete composition together rather than animating before artwork.
  final ValueChanged<String>? onImageSettled;

  /// A full-screen backdrop is the one image the screen is about, so its
  /// fetch goes ahead of the cards built alongside it. Callers that supply
  /// [imageBuilder] set the lane on their own image.
  final ImageFetchPriority priority;

  const FullscreenBackdropSwitcher({
    super.key,
    required this.imageUrl,
    required this.duration,
    this.alignment = Alignment.topCenter,
    // The load fade. The crossfade between two backdrops is [duration].
    this.fadeInDuration = Duration.zero,
    this.imageBuilder,
    this.animateInitialImage = false,
    this.softenTransition = false,
    this.onImageSettled,
    this.priority = ImageFetchPriority.high,
  });

  @override
  State<FullscreenBackdropSwitcher> createState() =>
      _FullscreenBackdropSwitcherState();
}

class _FullscreenBackdropSwitcherState extends State<FullscreenBackdropSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _opacity;

  String? _currentUrl;
  String? _incomingUrl;
  String? _pendingUrl;
  String? _settledUrl;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: widget.softenTransition
          ? TvRevealTransition.curve
          : Curves.easeInOut,
    );
    if (widget.animateInitialImage) {
      _incomingUrl = widget.imageUrl;
    } else {
      _currentUrl = widget.imageUrl;
    }

    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) {
        return;
      }

      final pending = _pendingUrl;

      final shouldContinue = pending != null && pending != _incomingUrl;

      setState(() {
        _currentUrl = _incomingUrl;
        _incomingUrl = shouldContinue ? pending : null;
        _pendingUrl = null;
      });

      if (shouldContinue) {
        _beginTransition();
      }
    });
    if (widget.animateInitialImage && widget.imageBuilder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _incomingUrl != null) _beginTransition();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDuration();
  }

  void _updateDuration() {
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.duration;
  }

  void _beginTransition() {
    _controller.reset();
    // Custom builders own their image lifecycle. The default path below waits
    // for a decoded frame so a slow network cannot use up the fade offscreen.
    if (widget.imageBuilder != null) _controller.forward();
  }

  void _startTransitionFor(String url) {
    if (_incomingUrl != url || _controller.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _incomingUrl == url && !_controller.isAnimating) {
        _controller.forward();
      }
    });
  }

  void _imageSettled(String url) {
    if (url == widget.imageUrl && _settledUrl != url) {
      _settledUrl = url;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (url == _currentUrl || url == _incomingUrl)) {
          widget.onImageSettled?.call(url);
        }
      });
    }
    _startTransitionFor(url);
  }

  @override
  void didUpdateWidget(FullscreenBackdropSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.duration != widget.duration) {
      _updateDuration();
    }
    if (oldWidget.softenTransition != widget.softenTransition) {
      _opacity.curve = widget.softenTransition
          ? TvRevealTransition.curve
          : Curves.easeInOut;
    }

    final next = widget.imageUrl;
    final shown = _incomingUrl ?? _currentUrl;

    if (next == shown) {
      _pendingUrl = null;
      return;
    }

    if (next != null && next == _pendingUrl) {
      return;
    }

    if (next == null) {
      // Cleared: drop all backdrop state immediately.
      _controller.stop();

      setState(() {
        _currentUrl = null;
        _incomingUrl = null;
        _pendingUrl = null;
        _settledUrl = null;
      });

      return;
    }

    if (_controller.isAnimating) {
      _pendingUrl = next;
      return;
    }

    setState(() {
      _incomingUrl = next;
    });

    _beginTransition();
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(String imageUrl) {
    return widget.imageBuilder?.call(imageUrl) ??
        OfflineAwareImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          alignment: widget.alignment,
          fadeInDuration: widget.fadeInDuration,
          // A backdrop covers the whole screen, so on a portrait phone it
          // paints far wider than the screen. The aspect lets the decode
          // bound follow the painted width instead of the box width.
          sourceAspectRatio: 16 / 9,
          maxDecodeWidth: ArtworkDecode.maxSourceWidth,
          priority: widget.priority,
          imageBuilder: (context, provider) => Image(
            image: provider,
            fit: BoxFit.cover,
            alignment: widget.alignment,
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null || synchronous) _imageSettled(imageUrl);
              return child;
            },
          ),
          errorWidget: (_, _, _) {
            // Finish to the empty layer instead of leaving a previous title's
            // artwork pinned forever when the next image fails.
            _imageSettled(imageUrl);
            return const SizedBox.shrink();
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_currentUrl != null)
            KeyedSubtree(
              key: ValueKey(_currentUrl),
              child: _buildImage(_currentUrl!),
            ),
          if (_incomingUrl != null)
            if (widget.softenTransition)
              ClipRect(
                child: TvRevealTransition(
                  animation: _opacity,
                  child: KeyedSubtree(
                    key: ValueKey(_incomingUrl),
                    child: _buildImage(_incomingUrl!),
                  ),
                ),
              )
            else
              FadeTransition(
                opacity: _opacity,
                child: KeyedSubtree(
                  key: ValueKey(_incomingUrl),
                  child: _buildImage(_incomingUrl!),
                ),
              ),
        ],
      ),
    );
  }
}
