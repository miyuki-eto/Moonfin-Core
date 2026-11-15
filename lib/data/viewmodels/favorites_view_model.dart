import '../../config/app_features.dart';

import 'dart:async';

import '../../util/platform_detection.dart';

import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/network_errors.dart';
import '../models/aggregated_item.dart';
import '../repositories/mdblist_repository.dart';
import '../services/user_data_sync.dart';
import '../utils/blocked_ratings.dart';

enum FavoritesState { loading, ready, error }

class FavoritesViewModel extends ChangeNotifier {
  final MediaServerClient _client;
  final UserPreferences _prefs;
  final MdbListRepository _mdbListRepository;

  static const _rowLimit = 30;
  static const _prefKey = 'favorites';
  static const _browseFields =
      'Type,UserData,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear,Status,ImageTags,BackdropImageTags,ParentBackdropItemId,ParentBackdropImageTags,CriticRating,MediaStreams';

  static const List<FavoriteTypeFilter> rowTypes = [
    FavoriteTypeFilter.movie,
    FavoriteTypeFilter.series,
    FavoriteTypeFilter.episode,
    FavoriteTypeFilter.collection,
    FavoriteTypeFilter.person,
  ];

  FavoritesState _state = FavoritesState.loading;
  bool _isDisposed = false;
  FavoritesState get state => _state;

  Map<FavoriteTypeFilter, List<AggregatedItem>> _rowItems = {};
  Map<FavoriteTypeFilter, List<AggregatedItem>> get rowItems => _rowItems;

  int get totalCount => _viewStyle == FavoritesViewStyle.home
      ? _rowItems.values.fold(0, (sum, list) => sum + list.length)
      : _gridTotalCount;

  late LibrarySortBy _sortBy;
  LibrarySortBy get sortBy => _sortBy;
  List<LibrarySortBy> get sortOptions =>
      LibrarySortBy.optionsFor(isSeriesLibrary: true);

  late SortDirection _sortDirection;
  SortDirection get sortDirection => _sortDirection;

  late ImageType _imageType;
  ImageType get imageType => _imageType;

  late PosterSize _posterSize;
  PosterSize get posterSize => _posterSize;

  Object? _error;
  Object? get error => _error;
  bool _isNetworkError = false;
  bool get isNetworkError => _isNetworkError;

  AggregatedItem? _focusedItem;
  AggregatedItem? get focusedItem => _focusedItem;

  Map<String, double> _focusedRatings = const {};
  Map<String, double> get focusedRatings => _focusedRatings;

  ImageApi get imageApi => _client.imageApi;

  late FavoritesViewStyle _viewStyle;
  FavoritesViewStyle get viewStyle => _viewStyle;

  List<AggregatedItem> _gridItems = const [];
  List<AggregatedItem> get gridItems => _gridItems;

  int _gridTotalCount = 0;
  int get gridTotalCount => _gridTotalCount;

  bool _loadingMoreGrid = false;
  bool get loadingMoreGrid => _loadingMoreGrid;

  /// Rows are paged from what the server handed over rather than from what is
  /// on screen, because a page thinned by the ratings filter would otherwise
  /// rewind the cursor and ask for rows it already has.
  int _gridFetchedCount = 0;
  final Map<FavoriteTypeFilter, int> _rowFetchedCounts = {};

  bool get hasMoreGrid => _gridFetchedCount < _gridTotalCount;

  final Map<FavoriteTypeFilter, int> _rowTotalCounts = {};
  final Set<FavoriteTypeFilter> _inFlightPagingRowTypes = {};

  /// Total number of favorites of [type] on the server, used for tab labels.
  /// Falls back to the number of items already loaded when unknown.
  int rowTotalCount(FavoriteTypeFilter type) =>
      _rowTotalCounts[type] ?? (_rowItems[type]?.length ?? 0);

  FavoritesViewModel({
    required MediaServerClient client,
    required UserPreferences prefs,
    required MdbListRepository mdbListRepository,
  }) : _client = client,
       _prefs = prefs,
       _mdbListRepository = mdbListRepository {
    _sortBy = _prefs.get(UserPreferences.librarySortBy(_prefKey));
    if (!sortOptions.contains(_sortBy)) _sortBy = LibrarySortBy.name;
    _sortDirection = _prefs.get(UserPreferences.librarySortDirection(_prefKey));
    _imageType = PlatformDetection.isTV
        ? ImageType.poster
        : _prefs.get(UserPreferences.libraryImageType(_prefKey));
    _posterSize = _prefs.resolveScreenPosterSize(
      UserPreferences.favoritesPosterSize,
    );
    _viewStyle = PlatformDetection.isTV
        ? FavoritesViewStyle.library
        : _prefs.get(UserPreferences.favoritesViewStyle);
    userDataSync.addListener(_onUserDataChanged);
  }

  /// Updates watched state and removes unfavourited entries. Removing an entry
  /// before the paging cursor shifts the next server page back by one.
  void _onUserDataChanged() {
    var changed = false;
    var needsRefill = false;

    Map<FavoriteTypeFilter, List<AggregatedItem>>? rows;
    _rowItems.forEach((type, items) {
      final patched = _patchFavorites(items);
      if (identical(patched, items)) {
        return;
      }
      final removed = items.length - patched.length;
      _rowTotalCounts[type] = max(0, rowTotalCount(type) - removed);
      _rowFetchedCounts[type] = max(
        0,
        (_rowFetchedCounts[type] ?? items.length) - removed,
      );
      if (patched.isEmpty && rowTotalCount(type) > 0) {
        needsRefill = true;
      }
      rows ??= Map.of(_rowItems);
      if (patched.isEmpty) {
        rows!.remove(type);
      } else {
        rows![type] = patched;
      }
    });
    if (rows != null) {
      _rowItems = rows!;
      changed = true;
    }

    final grid = _patchFavorites(_gridItems);
    if (!identical(grid, _gridItems)) {
      final removed = _gridItems.length - grid.length;
      _gridTotalCount = max(0, _gridTotalCount - removed);
      _gridFetchedCount = max(0, _gridFetchedCount - removed);
      _gridItems = grid;
      if (grid.isEmpty && hasMoreGrid) {
        needsRefill = true;
      }
      changed = true;
    }

    final focused = userDataSync.applyOrNull(_focusedItem);
    if (!identical(focused, _focusedItem)) {
      _focusedItem = _isUnfavorited(focused) ? null : focused;
      if (_focusedItem == null) {
        _focusedRatings = const {};
      }
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
    // Clearing every loaded entry must not hide favorites on later pages.
    // Reload from zero because removals have changed the server offsets.
    if (needsRefill && !_isDisposed) {
      unawaited(load());
    }
  }

  static bool _isUnfavorited(AggregatedItem? item) =>
      switch (item?.rawData['UserData']) {
        {'IsFavorite': false} => true,
        _ => false,
      };

  static List<AggregatedItem> _patchFavorites(List<AggregatedItem> items) {
    final patched = userDataSync.applyAll(items);
    // A favorite query may omit the flag. Only an explicit removal should
    // filter an entry; an unrelated watched update must keep it.
    if (!patched.any(_isUnfavorited)) {
      return patched;
    }
    return patched.where((item) => !_isUnfavorited(item)).toList();
  }

  @override
  void dispose() {
    _isDisposed = true;
    userDataSync.removeListener(_onUserDataChanged);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void setFocusedItem(AggregatedItem? item) {
    _focusedItem = item;
    _focusedRatings = const {};
    notifyListeners();
    if (item != null) {
      _loadFocusedRatings(item);
    }
  }

  Future<void> setViewStyle(FavoritesViewStyle value) async {
    if (_viewStyle == value) {
      return;
    }
    _viewStyle = value;
    await _prefs.set(UserPreferences.favoritesViewStyle, value);
    await load();
  }

  Future<void> _loadFocusedRatings(AggregatedItem item) async {
    if (!_prefs.get(UserPreferences.enableAdditionalRatings)) {
      return;
    }
    final ratings = await _mdbListRepository.getRatingsForItem(
      item,
      episodeRatingsEnabled: _prefs.canFetchEpisodeRatings,
    );
    if (ratings != null && ratings.isNotEmpty && _focusedItem?.id == item.id) {
      _focusedRatings = ratings;
      notifyListeners();
    }
  }

  Future<void> load() async {
    _state = FavoritesState.loading;
    _rowItems = {};
    _rowTotalCounts.clear();
    _rowFetchedCounts.clear();
    _gridItems = const [];
    _gridTotalCount = 0;
    _gridFetchedCount = 0;
    notifyListeners();

    try {
      if (_viewStyle == FavoritesViewStyle.home) {
        final results = await Future.wait(
          rowTypes.map((type) => _fetchRowItems(type, startIndex: 0)),
        );
        final map = <FavoriteTypeFilter, List<AggregatedItem>>{};
        for (var i = 0; i < rowTypes.length; i++) {
          if (results[i].$1.isNotEmpty) {
            map[rowTypes[i]] = results[i].$1;
            _rowTotalCounts[rowTypes[i]] = results[i].$2;
          }
        }
        _rowItems = map;
      } else {
        await _fetchGridPage(0);
      }
      _state = FavoritesState.ready;
    } catch (e) {
      _error = e;
      _isNetworkError = isNetworkException(e);
      _state = FavoritesState.error;
    }
    notifyListeners();
  }

  Future<(List<AggregatedItem>, int)> _fetchRowItems(
    FavoriteTypeFilter type, {
    int startIndex = 0,
  }) async {
    try {
      final sortValue = _sortBy.apiValue;
      final sortOrder = _sortDirection == SortDirection.ascending
          ? 'Ascending'
          : 'Descending';
      Map<String, dynamic> response;
      try {
        response = await _client.itemsApi.getItems(
          sortBy: sortValue,
          sortOrder: sortOrder,
          startIndex: startIndex,
          limit: _rowLimit,
          recursive: true,
          isFavorite: true,
          includeItemTypes: type.itemTypes,
          fields: _browseFields,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode ?? 0;
        if (statusCode < 500) {
          rethrow;
        }
        final fallbackSort = sortValue.toLowerCase().contains('isfolder')
            ? 'SortName'
            : sortValue;
        response = await _client.itemsApi.getItems(
          sortBy: fallbackSort,
          sortOrder: sortOrder,
          startIndex: startIndex,
          limit: _rowLimit,
          recursive: true,
          isFavorite: true,
          includeItemTypes: type.itemTypes,
          fields: _browseFields,
          enableTotalRecordCount: false,
        );
      }
      final rawItems = (response['Items'] as List?) ?? [];
      final items = rawItems
          .cast<Map<String, dynamic>>()
          .map(
            (raw) => AggregatedItem(
              id: raw['Id']?.toString() ?? '',
              serverId: _client.baseUrl,
              rawData: raw,
            ),
          )
          .toList();
      _rowFetchedCounts[type] = startIndex + rawItems.length;
      final totalCount = response['TotalRecordCount'] as int? ?? items.length;
      return (withoutBlockedItems(items), totalCount);
    } catch (_) {
      return (const <AggregatedItem>[], 0);
    }
  }

  Future<void> loadMoreForType(FavoriteTypeFilter type) async {
    final items = _rowItems[type];
    if (items == null || items.isEmpty) {
      return;
    }
    final total = _rowTotalCounts[type] ?? 0;
    final fetched = _rowFetchedCounts[type] ?? items.length;
    if (fetched >= total) {
      return;
    }
    if (_inFlightPagingRowTypes.contains(type)) {
      return;
    }

    _inFlightPagingRowTypes.add(type);
    try {
      final currentOffset = fetched;
      final (newItems, totalCount) = await _fetchRowItems(
        type,
        startIndex: currentOffset,
      );
      _rowTotalCounts[type] = totalCount;

      if (newItems.isNotEmpty) {
        _rowItems[type] = [...items, ...newItems];
        notifyListeners();
      } else {
        _rowTotalCounts[type] = items.length;
      }
    } catch (_) {
    } finally {
      _inFlightPagingRowTypes.remove(type);
    }
  }

  Future<void> _fetchGridPage(int startIndex) async {
    final sortValue = _sortBy.apiValue;
    final sortOrder = _sortDirection == SortDirection.ascending
        ? 'Ascending'
        : 'Descending';
    final pageSize = startIndex == 0 ? 75 : 48;

    Map<String, dynamic> response;
    try {
      response = await _client.itemsApi.getItems(
        sortBy: sortValue,
        sortOrder: sortOrder,
        startIndex: startIndex,
        limit: pageSize,
        recursive: true,
        isFavorite: true,
        includeItemTypes: AppFeatures.browseTypes,
        fields: _browseFields,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      if (statusCode < 500) {
        rethrow;
      }
      final fallbackSort = sortValue.toLowerCase().contains('isfolder')
          ? 'SortName'
          : sortValue;
      response = await _client.itemsApi.getItems(
        sortBy: fallbackSort,
        sortOrder: sortOrder,
        startIndex: startIndex,
        limit: pageSize,
        recursive: true,
        isFavorite: true,
        includeItemTypes: AppFeatures.browseTypes,
        fields: _browseFields,
        enableTotalRecordCount: false,
      );
    }

    final rawItems = (response['Items'] as List?) ?? [];
    final totalFromServer = response['TotalRecordCount'] as int?;
    if (totalFromServer != null) {
      _gridTotalCount = totalFromServer;
    } else {
      _gridTotalCount =
          startIndex + rawItems.length + (rawItems.length == pageSize ? 1 : 0);
    }

    final mapped = withoutBlockedItems(
      rawItems
          .cast<Map<String, dynamic>>()
          .map(
            (raw) => AggregatedItem(
              id: raw['Id']?.toString() ?? '',
              serverId: _client.baseUrl,
              rawData: raw,
            ),
          )
          .toList(),
    );

    _gridFetchedCount = startIndex + rawItems.length;

    if (startIndex == 0) {
      _gridItems = mapped;
    } else {
      _gridItems = [..._gridItems, ...mapped];
    }
  }

  Future<void> loadMoreGrid() async {
    if (_loadingMoreGrid || !hasMoreGrid) {
      return;
    }
    _loadingMoreGrid = true;
    notifyListeners();

    final prevFetched = _gridFetchedCount;
    try {
      await _fetchGridPage(_gridFetchedCount);
      if (_gridFetchedCount <= prevFetched) {
        _gridTotalCount = _gridFetchedCount;
      }
    } catch (_) {}

    _loadingMoreGrid = false;
    notifyListeners();
  }

  Future<void> setSortBy(LibrarySortBy value) async {
    if (_sortBy == value) {
      return;
    }
    _sortBy = value;
    await _prefs.set(UserPreferences.librarySortBy(_prefKey), value);
    await load();
  }

  Future<void> setSortDirection(SortDirection value) async {
    if (_sortDirection == value) {
      return;
    }
    _sortDirection = value;
    await _prefs.set(UserPreferences.librarySortDirection(_prefKey), value);
    await load();
  }

  Future<void> toggleSortDirection() => setSortDirection(
    _sortDirection == SortDirection.ascending
        ? SortDirection.descending
        : SortDirection.ascending,
  );

  Future<void> setImageType(ImageType value) async {
    if (_imageType == value) {
      return;
    }
    _imageType = value;
    await _prefs.set(UserPreferences.libraryImageType(_prefKey), value);
    notifyListeners();
  }

  Future<void> setPosterSize(PosterSize value) async {
    if (_posterSize == value) {
      return;
    }
    _posterSize = value;
    await _prefs.set(UserPreferences.favoritesPosterSize, value);
    notifyListeners();
  }
}
