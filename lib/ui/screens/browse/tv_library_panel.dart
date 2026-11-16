import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/viewmodels/library_browse_view_model.dart';
import '../../../data/models/aggregated_library.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../tv/tv26_button.dart';
import '../../tv/tv26_style.dart';
import '../../widgets/tv_navigation_button.dart';

/// Category navigation replaces the settings toolbar on the TV library page.
/// Every entry operates on the existing server query and its real facet values.
class TvLibraryPanel extends StatefulWidget {
  final LibraryBrowseViewModel viewModel;
  final FocusScopeNode scopeNode;
  final FocusNode homeFocusNode;
  final FocusNode categoryFocusNode;
  final VoidCallback onHome;
  final VoidCallback onExitRight;
  final Future<List<AggregatedLibrary>> libraries;
  final ValueChanged<AggregatedLibrary> onOpenLibrary;

  const TvLibraryPanel({
    super.key,
    required this.viewModel,
    required this.scopeNode,
    required this.homeFocusNode,
    required this.categoryFocusNode,
    required this.onHome,
    required this.onExitRight,
    required this.libraries,
    required this.onOpenLibrary,
  });

  @override
  State<TvLibraryPanel> createState() => _TvLibraryPanelState();
}

class _TvLibraryPanelState extends State<TvLibraryPanel> {
  final _categoryNodes = <String, FocusNode>{};
  String? _initialCategory;

  LibraryBrowseViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    for (final node in _categoryNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _recent() async {
    await viewModel.clearFilters();
    await viewModel.setSortDirection(SortDirection.descending);
    await viewModel.setSortBy(LibrarySortBy.dateAdded);
  }

  Future<void> _library(AggregatedLibrary library) async {
    if (library.id != viewModel.libraryId) {
      widget.onOpenLibrary(library);
      return;
    }
    await viewModel.clearFilters();
    await viewModel.setSortBy(LibrarySortBy.name);
    await viewModel.setSortDirection(SortDirection.ascending);
  }

  Future<void> _genre(String genre) async {
    await viewModel.clearFilters();
    await viewModel.toggleGenreFilter(genre);
  }

  Future<void> _quality() async {
    await viewModel.clearFilters();
    await viewModel.toggleVideoQualityFilter(LibraryVideoQualityFilter.uhd);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AggregatedLibrary>>(
    future: widget.libraries,
    builder: (context, snapshot) =>
        _buildPanel(context, snapshot.data ?? const []),
  );

  Widget _buildPanel(BuildContext context, List<AggregatedLibrary> libraries) {
    final vm = viewModel;
    final l10n = AppLocalizations.of(context);
    final uhd = vm.videoQualityFilters.contains(LibraryVideoQualityFilter.uhd);
    AggregatedLibrary? library(String type) {
      final matching = libraries.where((lib) => lib.collectionType == type);
      return matching.where((lib) => lib.id == vm.libraryId).firstOrNull ??
          matching.firstOrNull;
    }

    final movies = library('movies');
    final shows = library('tvshows');
    final genres = vm.facetValues.genres;
    final selectedGenre = vm.genreFilters.where(genres.contains).firstOrNull;
    final recent =
        !uhd &&
        selectedGenre == null &&
        (vm.sortBy == LibrarySortBy.dateAdded || vm.hasActiveFilters);
    const preferred = [
      'Action',
      'Adventure',
      'Comedy',
      'Drama',
      'Family',
      'Science Fiction',
      'Fantasy',
    ];
    final orderedGenres = [
      ...preferred.where(genres.contains),
      ...genres.where((genre) => !preferred.contains(genre)),
    ];

    Widget category(
      String label,
      IconData icon,
      VoidCallback onPressed, {
      bool selected = false,
      String? id,
    }) {
      final identity = id ?? label;
      // Selection changes query state; it must not move a FocusNode from one
      // button to another and dispose the control the remote is still using.
      if (selected) _initialCategory ??= identity;
      final node = identity == _initialCategory
          ? widget.categoryFocusNode
          : _categoryNodes.putIfAbsent(
              identity,
              () => FocusNode(debugLabel: 'libraryCategory:$identity'),
            );
      return Padding(
        key: ValueKey(identity),
        padding: const EdgeInsets.only(bottom: 2),
        child: Tv26Button(
          label: label,
          icon: icon,
          width: 190,
          height: 43,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          foregroundColor: const Color(0xFFBDBDBD),
          iconSize: 18,
          focusNode: node,
          transparent: true,
          contentAlignment: MainAxisAlignment.start,
          cornerRadius: Tv26Style.rowRadius,
          selected: selected,
          onUp: identity == l10n.recentlyAdded
              ? widget.homeFocusNode.requestFocus
              : null,
          onRight: widget.onExitRight,
          onPressed: onPressed,
        ),
      );
    }

    return SizedBox(
      width: Tv26Style.libraryPanelWidth,
      child: FocusScope(
        node: widget.scopeNode,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onExitRight();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned(
              left: 20,
              top: 30,
              child: TvNavigationButton(
                focusNode: widget.homeFocusNode,
                label: l10n.library,
                icon: CupertinoIcons.rectangle_stack_fill,
                onOpen: widget.onHome,
                onExitRight: widget.onExitRight,
              ),
            ),
            Positioned(
              left: 27,
              right: 21,
              top: 95,
              bottom: 24,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    category(
                      l10n.recentlyAdded,
                      CupertinoIcons.clock,
                      () => unawaited(_recent()),
                      selected: recent,
                    ),
                    if (movies != null)
                      category(
                        l10n.movies,
                        CupertinoIcons.film,
                        () => unawaited(_library(movies)),
                        selected:
                            !recent &&
                            movies.id == vm.libraryId &&
                            !vm.hasActiveFilters,
                      ),
                    if (shows != null)
                      category(
                        l10n.tvShows,
                        CupertinoIcons.tv,
                        () => unawaited(_library(shows)),
                        selected:
                            !recent &&
                            shows.id == vm.libraryId &&
                            !vm.hasActiveFilters,
                      ),
                    category(
                      '4K',
                      CupertinoIcons.tv,
                      () => unawaited(_quality()),
                      selected: uhd,
                    ),
                    const SizedBox(height: 58),
                    Padding(
                      padding: const EdgeInsets.only(left: 9, bottom: 9),
                      child: Text(
                        l10n.genres,
                        style: Tv26Style.text(
                          13,
                          color: const Color(0xFF777777),
                        ),
                      ),
                    ),
                    for (final genre in orderedGenres)
                      category(
                        genre,
                        switch (genre) {
                          'Comedy' => CupertinoIcons.smiley,
                          'Drama' => CupertinoIcons.person_2,
                          'Family' => CupertinoIcons.heart,
                          'Science Fiction' ||
                          'Fantasy' => CupertinoIcons.sparkles,
                          _ => CupertinoIcons.burst,
                        },
                        () => unawaited(_genre(genre)),
                        selected: !uhd && genre == selectedGenre,
                        id: 'genre:$genre',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
