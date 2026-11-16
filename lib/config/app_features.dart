/// Product scope for this video client. Saved server preferences cannot enable
/// features omitted from the fork. This is not a user-facing settings system.
enum AppFeature {
  video,
  liveTv,
  seerr,
  syncPlay,
  music,
  books,
  photos,
  games,
  downloads,
  casting,
  social,
  serverMessages,
  settings,
  administration,
  surfing,
  playlists,
}

abstract final class AppFeatures {
  static const _enabled = {AppFeature.video};

  static bool has(AppFeature feature) => _enabled.contains(feature);

  static const videoTypes = ['Movie', 'Series', 'Season', 'Episode', 'Video'];
  static const browseTypes = [...videoTypes, 'BoxSet', 'Person'];

  static bool allowsLibrary(String? collectionType) => const {
    '',
    'movies',
    'tvshows',
    'boxsets',
    'homevideos',
    'mixed',
  }.contains((collectionType ?? '').toLowerCase());

  static bool allowsItem(String? type) => const {
    ...browseTypes,
    'Trailer',
    'Folder',
    'CollectionFolder',
    'UserView',
    'Genre',
    'Studio',
  }.contains(type);

  static bool allowsRoute(String path) {
    const excluded = [
      '/settings',
      '/admin',
      '/setup',
      '/live-tv',
      '/seerr',
      '/music',
      '/books',
      '/games',
      '/game',
      '/game-player',
      '/romm-account',
      '/player/audio',
      '/player/book',
      '/player/photo',
      '/player/next-up',
      '/player/still-watching',
    ];
    return !excluded.any(
      (prefix) => path == prefix || path.startsWith('$prefix/'),
    );
  }
}
