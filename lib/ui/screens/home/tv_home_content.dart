import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/home_row.dart';
import '../../../data/models/media_bar_slide_item.dart';
import '../../../data/models/media_bar_state.dart';
import '../../widgets/mediabar/tv_featured_hero.dart';
import '../../../l10n/app_localizations.dart';
import '../../../platform/web_startup_splash.dart';
import '../../../preference/user_preferences.dart';
import '../../navigation/destinations.dart';
import '../../tv/tv26_style.dart';
import '../../tv/tv26_button.dart';
import '../../tv/tv_reveal_transition.dart';
import '../../widgets/focus/can_claim_initial_focus.dart';
import '../../tv/tv_card_focus_frame.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/mediabar/banner_media_bar.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/startup_loading.dart';
import '../../widgets/scroll_edge_fade.dart';
import '../../widgets/quick_return_wrapper.dart';
import 'home_view_model.dart';

/// The TV presentation consumes the existing Home model; row fetching, paging,
/// server selection and playback destinations remain owned by Moonfin.
class TvHomeContent extends StatefulWidget {
  final HomeViewModel viewModel;
  final UserPreferences prefs;
  final String? Function(AggregatedItem item) imageUrl;
  final ValueChanged<AggregatedItem?> onItemSelected;
  final void Function(HomeRow row, AggregatedItem item) onOpenItem;
  final void Function(HomeRow row, AggregatedItem item) onItemMenu;

  /// Navigation belongs inside the same loading and entrance boundary as Home.
  final Widget Function(Widget content)? pageBuilder;

  const TvHomeContent({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.imageUrl,
    required this.onItemSelected,
    required this.onOpenItem,
    required this.onItemMenu,
    this.pageBuilder,
  });

  @override
  State<TvHomeContent> createState() => _TvHomeContentState();
}

class _TvHomeContentState extends State<TvHomeContent> {
  static const _rowExtent =
      26.4 + Tv26Style.railTitleGap + 146 + Tv26Style.sectionGap;
  final _scroll = ScrollController();
  final _currentItem = ValueNotifier<MediaBarSlideItem?>(null);
  final _artworkReady = ValueNotifier<String?>(null);
  final _featured = FocusNode(debugLabel: 'tvHomeFeatured');
  final _rowNodes = <String, FocusNode>{};
  final _rowKeys = <String, GlobalKey>{};
  bool _presented = false;
  String? _initialArtworkUrl;
  bool _artworkSettled = false;
  bool _artworkTimedOut = false;
  Timer? _artworkWait;

  bool get _entranceReady => _initialArtworkUrl == null || _artworkSettled;

  void _onArtworkSettled(String url) {
    _artworkReady.value = url;
    if (_artworkSettled || url != _initialArtworkUrl) return;
    _revealHome();
  }

  void _revealHome({bool artworkTimedOut = false}) {
    if (!mounted || _artworkSettled) return;
    _artworkWait?.cancel();
    setState(() {
      _artworkSettled = true;
      _artworkTimedOut = artworkTimedOut;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
  }

  Widget _entrance(Widget content) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: !_entranceReady,
        child: IgnorePointer(
          ignoring: !_entranceReady,
          child: TvContentReveal(
            ready: _entranceReady,
            child: widget.pageBuilder?.call(content) ?? content,
          ),
        ),
      ),
      if (!_entranceReady) const StartupLoading(key: ValueKey('home-loading')),
    ],
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadSectionsNearViewport);
  }

  List<HomeRow> get _rows {
    final all = widget.viewModel.rows;
    bool continuing(HomeRow row) =>
        row.rowType == HomeRowType.resume || row.rowType == HomeRowType.nextUp;
    return [
      ...all.where(continuing),
      ...all.where((row) => !continuing(row)),
    ].where((row) => row.items.isNotEmpty || row.isLoading).toList();
  }

  bool get _hasHero =>
      widget.viewModel.mediaBarViewModel.items.isNotEmpty ||
      widget.viewModel.mediaBarViewModel.state is MediaBarLoading ||
      widget.viewModel.mediaBarViewModel.state is MediaBarError;

  void _loadSectionsNearViewport() {
    if (!_scroll.hasClients || !widget.viewModel.hasDeferredSections) return;
    final rows = _rows;
    final viewport = _scroll.position.viewportDimension;
    final heroHeight = _hasHero ? Tv26Style.homeHeroHeight : 90.0;
    final from = ((_scroll.offset - heroHeight - viewport) / _rowExtent)
        .floor();
    final to = ((_scroll.offset - heroHeight + 2 * viewport) / _rowExtent)
        .ceil();
    widget.viewModel.loadSectionsNear([
      for (var i = 0; i < rows.length; i++)
        if (i >= from && i <= to) rows[i],
    ]);
  }

  @override
  void dispose() {
    _artworkWait?.cancel();
    _currentItem.dispose();
    _artworkReady.dispose();
    _scroll.dispose();
    _featured.dispose();
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusEntry() {
    if (!mounted) return;
    if (_entranceReady && ModalRoute.of(context)?.isCurrent != false) {
      finishWebStartupSplash();
    }
    if (!canClaimInitialFocus(context)) return;
    if (_featured.context?.mounted ?? false) {
      _featured.requestFocus();
    } else {
      final first = _rows.where((row) => row.items.isNotEmpty).firstOrNull;
      if (first != null) _focusRow(first);
    }
  }

  Future<void> _retryEmptyHome() async {
    await widget.viewModel.refresh();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
  }

  void _top() {
    if (_featured.context?.mounted ?? false) {
      _featured.requestFocus();
    } else {
      NavigationLayout.focusNavbar();
    }
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _focusRow(HomeRow row) {
    _rowNodes
        .putIfAbsent(row.id, () => FocusNode(debugLabel: row.id))
        .requestFocus();
    final context = _rowKeys[row.id]?.currentContext;
    if (context != null) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.viewModel,
      widget.viewModel.mediaBarViewModel,
      widget.prefs,
    ]),
    builder: (context, _) {
      final allRows = widget.viewModel.rows;
      final rows = _rows;
      if (widget.viewModel.hasDeferredSections) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadSectionsNearViewport();
        });
      }
      if (!_presented) {
        final hasRows = rows.any((row) => row.items.isNotEmpty);
        final heroPending =
            widget.viewModel.mediaBarViewModel.state is MediaBarLoading;
        if (heroPending || (!hasRows && widget.viewModel.isLoading)) {
          return const Stack(
            fit: StackFit.expand,
            children: [StartupLoading(key: ValueKey('home-loading'))],
          );
        }
        _presented = true;
        _initialArtworkUrl =
            widget.viewModel.mediaBarViewModel.items.firstOrNull?.backdropUrl;
        if (!_entranceReady) {
          // Artwork is optional: a stalled request must not hold the page.
          _artworkWait = Timer(
            const Duration(seconds: 5),
            () => _revealHome(artworkTimedOut: true),
          );
        }
        if (_entranceReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
        }
      }
      if (rows.isEmpty && !_hasHero) {
        final l10n = AppLocalizations.of(context);
        return _entrance(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.noItems, style: Tv26Style.text(22)),
                const SizedBox(height: 20),
                Tv26Button(
                  label: l10n.refresh,
                  focusNode: _featured,
                  onPressed: () => unawaited(_retryEmptyHome()),
                  onUp: () => NavigationLayout.focusNavbar(),
                  onLeft: () => NavigationLayout.focusNavbar(),
                ),
              ],
            ),
          ),
        );
      }
      final content = ColoredBox(
        color: Colors.black,
        child: QuickReturnWrapper(
          scrollController: _scroll,
          topFocusNode: _featured,
          onReturn: _top,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_currentItem, _scroll]),
                  builder: (context, _) => Opacity(
                    opacity:
                        (_scroll.hasClients ? 1.0 - _scroll.offset / 400 : 1.0)
                            .clamp(0.0, 1.0),
                    child: TvFeaturedArtwork(
                      key: ValueKey(_artworkTimedOut),
                      imageUrl:
                          _currentItem.value?.backdropUrl ?? _initialArtworkUrl,
                      animateInitialImage: _artworkTimedOut,
                      onImageSettled: _onArtworkSettled,
                    ),
                  ),
                ),
              ),
              ScrollEdgeFade(
                startInset: 80,
                fadeAfterAtStart: !_hasHero,
                child: CustomScrollView(
                  controller: _scroll,
                  clipBehavior: Clip.hardEdge,
                  slivers: [
                    if (!_hasHero)
                      const SliverToBoxAdapter(child: SizedBox(height: 90)),
                    if (_hasHero)
                      SliverToBoxAdapter(
                        child: BannerMediaBar(
                          artworkReady: _artworkReady,
                          viewModel: widget.viewModel.mediaBarViewModel,
                          prefs: widget.prefs,
                          height: Tv26Style.homeHeroHeight,
                          showArtwork: false,
                          externallyPaused:
                              !_entranceReady || !canClaimInitialFocus(context),
                          onCurrentItem: (item) => _currentItem.value = item,
                          focusNode: _featured,
                          onNavigateDown: () async {
                            if (rows.isNotEmpty) _focusRow(rows.first);
                          },
                          onNavigateUp: () => NavigationLayout
                              .focusNavbarNotifier
                              .value
                              ?.call(),
                          onNavigateLeft: () => NavigationLayout
                              .focusNavbarNotifier
                              .value
                              ?.call(),
                          onOpen: (item) => context.push(
                            Destinations.item(
                              item.itemId,
                              serverId: item.serverId,
                            ),
                          ),
                          onPlay: (item) => context.push(
                            Destinations.item(
                              item.itemId,
                              serverId: item.serverId,
                              autoPlay: true,
                            ),
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, rowIndex) {
                        final row = rows[rowIndex];
                        final rowNode = _rowNodes.putIfAbsent(
                          row.id,
                          () => FocusNode(debugLabel: row.id),
                        );
                        final rowKey = _rowKeys.putIfAbsent(
                          row.id,
                          GlobalKey.new,
                        );
                        final title =
                            row.rowType == HomeRowType.resume ||
                                row.rowType == HomeRowType.nextUp
                            ? AppLocalizations.of(context).continueWatching
                            : row.title;
                        return Padding(
                          key: rowKey,
                          padding: const EdgeInsets.only(
                            bottom: Tv26Style.sectionGap,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: Tv26Style.inset,
                                ),
                                child: Text(
                                  title,
                                  style: Tv26Style.sectionTitle,
                                ),
                              ),
                              const SizedBox(height: Tv26Style.railTitleGap),
                              if (row.items.isEmpty)
                                SizedBox(
                                  height: 146,
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 48),
                                      for (var i = 0; i < 5; i++)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: Tv26Style.railItemGap,
                                            bottom: 39,
                                          ),
                                          child: Container(
                                            width: 190,
                                            height: 107,
                                            decoration: BoxDecoration(
                                              color: Tv26Style.background,
                                              borderRadius:
                                                  BorderRadius.circular(13),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              else
                                LockedFocusRow<AggregatedItem>(
                                  items: row.items,
                                  itemKey: (item, _) =>
                                      '${item.serverId}:${item.id}',
                                  preserveFocusedItemOnRefresh: true,
                                  hubKey: 'tv26_${row.id}',
                                  focusNode: rowNode,
                                  itemExtent: 190 + Tv26Style.railItemGap,
                                  height: 146,
                                  paintOutset: Tv26Style.focusOutset,
                                  padding: Tv26Style.railPadding.copyWith(
                                    top: 6,
                                  ),
                                  clipBehavior: Clip.none,
                                  onLeftEdge: () => NavigationLayout
                                      .focusNavbarNotifier
                                      .value
                                      ?.call(),
                                  onBack: _top,
                                  onVerticalNavigation: (up) {
                                    if (up && rowIndex == 0) {
                                      _top();
                                      return true;
                                    }
                                    final next = rowIndex + (up ? -1 : 1);
                                    if (next >= 0 && next < rows.length) {
                                      _focusRow(rows[next]);
                                    }
                                    return true;
                                  },
                                  onIndexChanged: (index, item) {
                                    widget.onItemSelected(item);
                                    final original = allRows.indexOf(row);
                                    if (index >= row.items.length - 4 &&
                                        original >= 0) {
                                      unawaited(
                                        widget.viewModel.loadMoreForRow(
                                          original,
                                        ),
                                      );
                                    }
                                  },
                                  onTap: (_, item) =>
                                      widget.onOpenItem(row, item),
                                  onLongPress: (_, item) =>
                                      widget.onItemMenu(row, item),
                                  itemBuilder: (context, item, _, focused) =>
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: Tv26Style.railItemGap,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 190,
                                              height: 107,
                                              child: TvCardFocusFrame(
                                                focused: focused,
                                                child:
                                                    widget.imageUrl(item) !=
                                                        null
                                                    ? BoundedNetworkImage(
                                                        imageUrl: widget
                                                            .imageUrl(item)!,
                                                        maxWidth: 640,
                                                      )
                                                    : ColoredBox(
                                                        color: Tv26Style
                                                            .background,
                                                        child: Center(
                                                          child: Text(
                                                            item.name,
                                                            style:
                                                                Tv26Style.text(
                                                                  14,
                                                                ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              item.seriesName ?? item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Tv26Style.text(13),
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height:
                            (MediaQuery.sizeOf(context).height - _rowExtent) /
                            2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      return _entrance(content);
    },
  );
}
