import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../util/platform_detection.dart';

import '../../../widgets/bottom_nav/bottom_navbar.dart';
import '../../../widgets/scroll_edge_fade.dart';
import '../../../tv/tv_detail_backdrop.dart';
import '../../../tv/tv_reveal_transition.dart';
import 'shared/nouveau_spacing.dart';
import 'hero/tv_detail_hero.dart';

class NouveauLandscapeLayout extends StatelessWidget {
  static const tvScrollStartInset =
      Tv26Style.detailTitleTop + Tv26Style.detailTitleHeight;
  static const tvSeasonTabsTop = tvScrollStartInset + Tv26Style.detailHeaderGap;

  final Widget backdrop;
  final Widget hero;
  final Widget? scrolledTitle;
  final List<Widget> sections;
  final ScrollController scrollController;

  final EdgeInsetsGeometry heroPadding;
  final EdgeInsetsGeometry firstSectionPadding;
  final EdgeInsetsGeometry remainingSectionsPadding;

  final bool compactFirstFold;
  final double compactHeroHeight;
  final double compactHeroToSectionSpacing;

  const NouveauLandscapeLayout({
    super.key,
    required this.backdrop,
    required this.hero,
    this.scrolledTitle,
    required this.sections,
    required this.scrollController,
    this.heroPadding = EdgeInsets.zero,
    this.firstSectionPadding = const EdgeInsets.fromLTRB(56, 0, 56, 0),
    this.remainingSectionsPadding = const EdgeInsets.fromLTRB(56, 0, 56, 0),
    this.compactFirstFold = false,
    this.compactHeroHeight = 370,
    this.compactHeroToSectionSpacing = 20,
  });

  Widget _buildScrollReveal(
    BuildContext context,
    Size size, {
    required Widget child,
    bool hideWithTitle = false,
  }) => AnimatedBuilder(
    animation: scrollController,
    child: child,
    builder: (context, child) {
      final titleVisible =
          scrollController.hasClients &&
          scrollController.offset >=
              TvDetailHeroFrame.heightForWidth(size.width) / 2;
      final visible = hideWithTitle ? !titleVisible : titleVisible;
      return IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: visible ? 1 : 0),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TvRevealTransition.duration,
            curve: TvRevealTransition.curve,
            child: child,
            builder: (context, progress, child) => TvRevealTransition(
              animation: AlwaysStoppedAnimation(progress),
              child: child!,
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final firstSection = sections.isNotEmpty
        ? sections.first
        : const SizedBox.shrink();

    final remainingSections = sections.length > 1
        ? sections.skip(1).toList(growable: false)
        : const <Widget>[];

    final resolvedHeroPadding = heroPadding.resolve(Directionality.of(context));

    final nonCompactHeroPadding = EdgeInsets.only(
      top: resolvedHeroPadding.top,
      left: resolvedHeroPadding.left,
      right: resolvedHeroPadding.right,
    );

    final compactHeroFrameHeight =
        compactHeroHeight + resolvedHeroPadding.vertical;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: PlatformDetection.isTV && !compactFirstFold
              ? TvDetailBackdrop(
                  scrollController: scrollController,
                  heroExtent: TvDetailHeroFrame.heightForWidth(size.width),
                  child: backdrop,
                )
              : backdrop,
        ),

        ScrollEdgeFade(
          startInset: PlatformDetection.isTV ? tvScrollStartInset : 0,
          startDistance: PlatformDetection.isTV && scrolledTitle != null
              ? Tv26Style.detailHeaderGap
              : null,
          child: CustomScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              if (compactFirstFold) ...[
                SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: size.height),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: compactHeroFrameHeight,
                          child: Padding(padding: heroPadding, child: hero),
                        ),

                        if (compactHeroToSectionSpacing > 0)
                          SizedBox(height: compactHeroToSectionSpacing),

                        Padding(
                          padding: firstSectionPadding,
                          child: firstSection,
                        ),
                      ],
                    ),
                  ),
                ),

                if (remainingSections.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: remainingSectionsPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: remainingSections,
                      ),
                    ),
                  ),
              ] else ...[
                SliverToBoxAdapter(
                  child: PlatformDetection.isTV
                      ? scrolledTitle == null
                            ? TvDetailHeroFrame(child: hero)
                            : _buildScrollReveal(
                                context,
                                size,
                                hideWithTitle: true,
                                child: TvDetailHeroFrame(child: hero),
                              )
                      : Padding(padding: nonCompactHeroPadding, child: hero),
                ),

                if (sections.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: NouveauSpacing.sectionGap),

                        Padding(
                          padding: firstSectionPadding,
                          child: firstSection,
                        ),

                        if (remainingSections.isNotEmpty)
                          Padding(
                            padding: remainingSectionsPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: remainingSections,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(height: bottomContentInset(context)),
              ),
            ],
          ),
        ),
        if (PlatformDetection.isTV && scrolledTitle != null)
          Positioned(
            top: Tv26Style.detailTitleTop,
            left: Tv26Style.inset,
            right: Tv26Style.inset,
            height: Tv26Style.detailTitleHeight,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: _buildScrollReveal(
                  context,
                  size,
                  child: Center(child: scrolledTitle),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
