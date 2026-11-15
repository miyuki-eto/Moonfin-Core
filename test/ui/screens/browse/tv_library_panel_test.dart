import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/viewmodels/library_browse_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/tv_library_grid.dart';
import 'package:moonfin/ui/screens/browse/tv_library_panel.dart';
import 'package:server_core/server_core.dart';

class _Model extends Mock implements LibraryBrowseViewModel {}

void main() {
  late _Model vm;
  const movies = AggregatedLibrary(
    id: 'movies',
    name: 'Movies',
    collectionType: 'movies',
    serverId: 'server',
  );
  const shows = AggregatedLibrary(
    id: 'shows',
    name: 'Shows',
    collectionType: 'tvshows',
    serverId: 'server',
  );

  setUp(() {
    vm = _Model();
    when(() => vm.libraryId).thenReturn('movies');
    when(() => vm.sortBy).thenReturn(LibrarySortBy.dateAdded);
    when(() => vm.hasActiveFilters).thenReturn(false);
    when(() => vm.videoQualityFilters).thenReturn({});
    when(() => vm.genreFilters).thenReturn({});
    when(() => vm.facetValues)
        .thenReturn(const QueryFilterValues(genres: ['Action', 'Drama']));
    when(() => vm.clearFilters()).thenAnswer((_) async {});
    when(() => vm.setSortDirection(SortDirection.descending))
        .thenAnswer((_) async {});
    when(() => vm.setSortBy(LibrarySortBy.dateAdded)).thenAnswer((_) async {});
    when(() => vm.toggleVideoQualityFilter(LibraryVideoQualityFilter.uhd))
        .thenAnswer((_) async {});
    when(() => vm.clearFilterGroup(LibraryFilterGroup.genres))
        .thenAnswer((_) async {});
    when(() => vm.toggleGenreFilter('Drama')).thenAnswer((_) async {});
  });

  testWidgets(
    'server categories navigate to real libraries and genres query real facets',
    (tester) async {
      tester.view.physicalSize = const Size(1145, 644);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = FocusScopeNode();
      final home = FocusNode();
      final category = FocusNode();
      addTearDown(scope.dispose);
      addTearDown(home.dispose);
      addTearDown(category.dispose);
      AggregatedLibrary? opened;
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: TvLibraryPanel(
              viewModel: vm,
              libraries: Future.value([movies, shows]),
              onOpenLibrary: (library) => opened = library,
              scopeNode: scope,
              homeFocusNode: home,
              categoryFocusNode: category,
              onHome: () {},
              onExitRight: () => exits++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent Purchases'), findsNothing);
      expect(find.text('Family Sharing'), findsNothing);
      expect(find.text('4K HDR'), findsNothing);
      await tester.tap(find.text('TV Shows'));
      expect(opened, shows);
      verifyNever(() => vm.setLibraryFilter(any()));
      await tester.tap(find.text('4K'));
      verify(() => vm.toggleVideoQualityFilter(LibraryVideoQualityFilter.uhd))
          .called(1);
      clearInteractions(vm);
      await tester.tap(find.text('Drama'));
      await tester.pump();
      verifyInOrder([
        () => vm.clearFilters(),
        () => vm.toggleGenreFilter('Drama'),
      ]);
      category.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('six poster columns keep the reference bounds across rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1145, 644);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 238),
              Expanded(
                child: TvLibraryGrid(
                  controller: controller,
                  itemCount: 18,
                  itemBuilder: (_, index) =>
                      ColoredBox(key: ValueKey(index), color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey(0))),
      const Rect.fromLTWH(263, 95, 119, 178.5),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey(5))),
      const Rect.fromLTWH(978, 95, 119, 178.5),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(6))),
      const Offset(263, 312.5),
    );
    await tester.drag(find.byType(GridView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
