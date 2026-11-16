import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';
import 'horizontal_scroll_section.dart';
import 'scroll_edge_fade.dart';
import 'media_card.dart';
import 'scroll_rail_viewport.dart';
import '../tv/tv26_button.dart';

class LibraryRow extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onSeeAll;
  final double? rowHeight;
  final ScrollController? scrollController;
  final bool isLoading;

  const LibraryRow({
    super.key,
    required this.title,
    required this.children,
    this.onSeeAll,
    this.rowHeight,
    this.scrollController,
    this.isLoading = false,
  });

  @override
  State<LibraryRow> createState() => _LibraryRowState();
}

class _LibraryRowState extends State<LibraryRow> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasItems = widget.children.isNotEmpty;
    final showControls = hasItems && PlatformDetection.useDesktopUi;
    if (PlatformDetection.isTV) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Tv26Style.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: Tv26Style.sectionTitle),
                ),
                if (widget.onSeeAll != null)
                  Tv26Button(label: l10n.seeAll, onPressed: widget.onSeeAll!),
              ],
            ),
            const SizedBox(height: Tv26Style.railTitleGap),
            ScrollRailViewport(
              height: widget.rowHeight ?? 220,
              viewportInsets: Tv26Style.railPadding,
              paintOutset: Tv26Style.focusOutset,
              builder: (context, padding) => ListView.separated(
                controller: widget.scrollController,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: padding,
                itemCount: widget.children.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: Tv26Style.railItemGap),
                itemBuilder: (_, index) => widget.children[index],
              ),
            ),
          ],
        ),
      );
    }
    final desktopScale = GetIt.instance<UserPreferences>()
        .get(UserPreferences.desktopUiScale)
        .scaleFactor;
    final cardFocusExpansion = GetIt.instance<UserPreferences>().get(
      UserPreferences.cardFocusExpansion,
    );
    final isMobile = PlatformDetection.useMobileUi;
    final baseHeight = widget.rowHeight ?? 220.0;
    final estArtworkHeight = (baseHeight - 45.0).clamp(60.0, 400.0);
    final upwardGrowth = cardFocusExpansion && !isMobile
        ? estArtworkHeight * (MediaCard.focusScale - 1.0)
        : 0.0;
    final rowHeight = (baseHeight * desktopScale) + upwardGrowth;
    final itemSpacing = cardFocusExpansion && !isMobile
        ? MediaCard.focusGap(130.0 * desktopScale, minimum: 12.0 * desktopScale)
        : (12.0 * desktopScale);
    final topPadding = (5.0 * desktopScale) + upwardGrowth;
    return HorizontalScrollSection(
      title: widget.title,
      scrollController: widget.scrollController,
      titleStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: AppColorScheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
      headerPadding: EdgeInsets.fromLTRB(
        16 * desktopScale,
        16 * desktopScale,
        8 * desktopScale,
        8 * desktopScale,
      ),
      contentSpacing: 0,
      trailing: widget.onSeeAll == null
          ? null
          : TextButton(onPressed: widget.onSeeAll, child: Text(l10n.seeAll)),
      showControls: showControls,
      builder: (_, scrollController) => SizedBox(
        height: rowHeight + (10 * desktopScale),
        child: widget.isLoading
            ? Center(
                child: SizedBox(
                  width: 24 * desktopScale,
                  height: 24 * desktopScale,
                  child: const LoadingThrobber(),
                ),
              )
            : hasItems
            ? ScrollEdgeFade(
                axis: Axis.horizontal,
                child: ListView.separated(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.fromLTRB(
                    20 * desktopScale,
                    topPadding,
                    20 * desktopScale,
                    5 * desktopScale,
                  ),
                  itemCount: widget.children.length,
                  separatorBuilder: (_, _) => SizedBox(width: itemSpacing),
                  itemBuilder: (_, i) => widget.children[i],
                ),
              )
            : Center(
                child: Text(
                  l10n.noItems,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                        .withAlpha(128),
                  ),
                ),
              ),
      ),
    );
  }
}
