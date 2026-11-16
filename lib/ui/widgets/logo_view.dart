import 'dart:ui' as ui;

import 'offline_aware_image.dart';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../util/platform_detection.dart';
import '../tv/tv_reveal_transition.dart';

/// A logo display widget with a drop shadow that follows the image shape.
class LogoView extends StatelessWidget {
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final double maxHeight;
  final double maxWidth;
  final Widget? fallback;

  const LogoView({
    super.key,
    this.imageUrl,
    this.imageProvider,
    this.maxHeight = 80,
    this.maxWidth = 200,
    this.fallback,
  });

  ImageProvider? get _effectiveProvider {
    if (imageProvider != null) return imageProvider;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return offlineAwareImageProvider(imageUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _effectiveProvider;
    if (provider == null) return fallback ?? const SizedBox.shrink();

    Widget artwork(Widget image) => Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 3,
              sigmaY: 3,
              tileMode: TileMode.decal,
            ),
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              color: AppColorScheme.scrim.withValues(alpha: 0.6),
              colorBlendMode: BlendMode.srcATop,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        image,
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
      child: Image(
        key: ValueKey(provider),
        image: provider,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, synchronous) {
          final loaded = frame != null || synchronous;
          final content = loaded
              ? artwork(child)
              : fallback ?? const SizedBox.shrink();
          if (!PlatformDetection.isTV) {
            return loaded ? content : artwork(content);
          }
          // RawImage belongs to ImageState's current ImageInfo. Retaining it
          // as an AnimatedSwitcher outgoing child can outlive that handle.
          return Stack(
            alignment: Alignment.center,
            children: [
              if (fallback != null)
                AnimatedOpacity(
                  opacity: loaded ? 0 : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : TvRevealTransition.duration,
                  child: fallback!,
                ),
              TvContentReveal(
                ready: loaded,
                child: loaded ? content : const SizedBox.shrink(),
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
      ),
    );
  }
}
