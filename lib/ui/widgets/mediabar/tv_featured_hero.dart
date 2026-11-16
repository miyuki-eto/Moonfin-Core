import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../data/models/media_bar_slide_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/overview_text.dart';
import '../../tv/tv26_button.dart';
import '../../tv/tv26_classification.dart';
import '../../tv/tv26_style.dart';
import '../../tv/tv_reveal_transition.dart';
import '../fullscreen_backdrop_switcher.dart';
import '../logo_view.dart';

class TvFeaturedHero extends StatefulWidget {
  final MediaBarSlideItem item;
  final bool showArtwork;
  final double height;
  final int index;
  final int count;
  final FocusNode? focusNode;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final VoidCallback onNext;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final ValueChanged<bool> onFocusChange;
  final ValueChanged<bool> onHoverChange;

  const TvFeaturedHero({
    super.key,
    required this.item,
    this.showArtwork = true,
    required this.height,
    required this.index,
    required this.count,
    required this.onOpen,
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
    required this.onFocusChange,
    required this.onHoverChange,
    this.onFavorite,
    this.isFavorite = false,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  @override
  State<TvFeaturedHero> createState() => _TvFeaturedHeroState();
}

class _TvFeaturedHeroState extends State<TvFeaturedHero> {
  final _play = FocusNode(debugLabel: 'featuredPlay');
  final _favorite = FocusNode(debugLabel: 'featuredFavorite');
  final _info = FocusNode(debugLabel: 'featuredInfo');
  final _next = FocusNode(debugLabel: 'featuredNext');

  @override
  void dispose() {
    _play.dispose();
    _favorite.dispose();
    _info.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = AppLocalizations.of(context);
    final hasFavorite = !item.isExternal && widget.onFavorite != null;
    final summary = cleanOverview(item.overview);
    final title = Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Tv26Style.text(36, weight: FontWeight.w700),
    );
    final dots = widget.count.clamp(0, 9);
    final firstDot = (widget.index - dots ~/ 2).clamp(0, widget.count - dots);

    Widget reveal(Widget child) => AnimatedSwitcher(
      duration: TvRevealTransition.duration,
      switchInCurve: TvRevealTransition.curve,
      switchOutCurve: TvRevealTransition.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) =>
          TvRevealTransition(animation: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey('${item.serverId}:${item.itemId}'),
        child: child,
      ),
    );

    Tv26Button action(
      String label,
      IconData icon,
      FocusNode node,
      VoidCallback onPressed,
      VoidCallback onLeft,
      VoidCallback onRight, {
      bool primary = false,
      bool transparent = false,
    }) => Tv26Button(
      label: label,
      icon: icon,
      focusNode: node,
      onPressed: onPressed,
      primary: primary,
      iconOnly: !primary,
      width: primary ? 137 : 40,
      height: 40,
      fontSize: 18,
      iconSize: primary ? 17 : 21,
      transparent: transparent,
      autofocus: primary && widget.focusNode == null,
      onUp: widget.onNavigateUp,
      onDown: widget.onNavigateDown,
      onLeft: onLeft,
      onRight: onRight,
      onHoverChange: widget.onHoverChange,
    );

    return MouseRegion(
      onEnter: (_) => widget.onHoverChange(true),
      onExit: (_) => widget.onHoverChange(false),
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: true,
        canRequestFocus: widget.focusNode != null,
        onFocusChange: (focused) {
          widget.onFocusChange(focused);
          if (focused && (widget.focusNode?.hasPrimaryFocus ?? false)) {
            _play.requestFocus();
          }
        },
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.showArtwork)
                Positioned.fill(
                  child: TvFeaturedArtwork(imageUrl: item.backdropUrl),
                ),
              Positioned(
                left: 48,
                bottom: 61,
                width: 470,
                height: 156,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      height: 43,
                      width: 250,
                      child: reveal(
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: item.logoUrl != null
                              ? LogoView(
                                  imageUrl: item.logoUrl,
                                  maxWidth: 250,
                                  maxHeight: 43,
                                  fallback: title,
                                )
                              : title,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 48,
                      width: 470,
                      child: reveal(
                        Tv26Classification(
                          isMovie: item.itemType != 'Series',
                          type: item.itemType == 'Series'
                              ? l10n.series
                              : l10n.movie,
                          genres: item.genres,
                          rating: item.officialRating,
                        ),
                      ),
                    ),
                    if (summary.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: 82,
                        width: 470,
                        child: reveal(
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tv26Style.text(
                              14,
                              color: Tv26Style.secondary,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: -3,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          action(
                            item.isExternal ? l10n.details : l10n.play,
                            item.isExternal
                                ? CupertinoIcons.info_circle
                                : CupertinoIcons.play_fill,
                            _play,
                            item.isExternal ? widget.onOpen : widget.onPlay,
                            widget.onPrevious,
                            () {
                              if (hasFavorite) {
                                _favorite.requestFocus();
                              } else if (!item.isExternal) {
                                _info.requestFocus();
                              } else if (widget.count > 1) {
                                _next.requestFocus();
                              }
                            },
                            primary: true,
                          ),
                          if (hasFavorite) ...[
                            const SizedBox(width: 12),
                            action(
                              l10n.favorites,
                              widget.isFavorite
                                  ? CupertinoIcons.check_mark
                                  : CupertinoIcons.plus,
                              _favorite,
                              widget.onFavorite!,
                              _play.requestFocus,
                              _info.requestFocus,
                            ),
                          ],
                          if (!item.isExternal) ...[
                            const SizedBox(width: 12),
                            action(
                              l10n.details,
                              CupertinoIcons.info_circle,
                              _info,
                              widget.onOpen,
                              () => (hasFavorite ? _favorite : _play)
                                  .requestFocus(),
                              () {
                                if (widget.count > 1) {
                                  _next.requestFocus();
                                }
                              },
                            ),
                          ],
                          if (widget.count > 1) ...[
                            const SizedBox(width: 4),
                            action(
                              l10n.next,
                              CupertinoIcons.chevron_right,
                              _next,
                              widget.onNext,
                              () => (item.isExternal ? _play : _info)
                                  .requestFocus(),
                              widget.onNext,
                              transparent: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.count > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -3,
                  child: Center(
                    child: Container(
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x60000000),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = firstDot;
                            index < firstDot + dots;
                            index++
                          )
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 5,
                              width: index == widget.index ? 17 : 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: index == widget.index
                                    ? Tv26Style.foreground
                                    : const Color(0x55FFFFFF),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen art belongs behind the scrollable rails, not to an overflowing
/// sliver (which Flutter paints above subsequent slivers).
class TvFeaturedArtwork extends StatelessWidget {
  final String? imageUrl;
  final bool animateInitialImage;
  final ValueChanged<String>? onImageSettled;
  const TvFeaturedArtwork({
    super.key,
    this.imageUrl,
    this.animateInitialImage = true,
    this.onImageSettled,
  });

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Colors.black),
      FullscreenBackdropSwitcher(
        imageUrl: imageUrl,
        duration: TvRevealTransition.duration,
        softenTransition: true,
        alignment: Alignment.center,
        animateInitialImage: animateInitialImage,
        onImageSettled: onImageSettled,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xAD000000), Color(0x26000000), Colors.transparent],
            stops: [0, .5, 1],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x40000000),
              Colors.transparent,
              Color(0x18000000),
              Colors.black,
            ],
            stops: [0, .28, .55, .96],
          ),
        ),
      ),
    ],
  );
}
