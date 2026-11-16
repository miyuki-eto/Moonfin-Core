import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/config/app_features.dart';
import 'package:moonfin/data/offline/connectivity_aware_media_server_client.dart';
import 'package:moonfin/data/services/connectivity_service.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _Offline extends Mock implements ConnectivityService {}

void main() {
  test('losing the server cannot switch browsing into the omitted downloads catalog', () async {
    final offline = _Offline();
    when(() => offline.canReachServer).thenReturn(false);
    GetIt.instance.registerSingleton<ConnectivityService>(offline);
    addTearDown(() => GetIt.instance.reset());
    expect(shouldUseOfflineCatalog(), isFalse);
  });
  test('saved preferences cannot enable removed product features', () {
    expect(AppFeature.values.where(AppFeatures.has), [AppFeature.video]);
  });
  test('all removed route families are blocked, including nested links', () {
    for (final path in [
      '/live-tv',
      '/live-tv/player',
      '/seerr/media/42',
      '/music/1',
      '/books/1/titles',
      '/games/1',
      '/game/1/2',
      '/game-player/1/2',
      '/romm-account',
      '/player/audio',
      '/player/photo/1',
      '/player/book/1',
      '/settings',
      '/admin/users',
      '/setup',
    ]) {
      expect(AppFeatures.allowsRoute(path), isFalse, reason: path);
    }
    for (final path in [
      '/home',
      '/search',
      '/genres',
      '/favorites',
      '/library/1',
      '/item/1',
      '/player/video',
      '/player/trailer',
      '/login',
      '/server-select',
    ]) {
      expect(AppFeatures.allowsRoute(path), isTrue, reason: path);
    }
  });
  test('catalog scope includes video and related people/collections only', () {
    for (final type in [
      'Movie',
      'Series',
      'Season',
      'Episode',
      'Video',
      'Person',
      'BoxSet',
    ]) {
      expect(AppFeatures.allowsItem(type), isTrue, reason: type);
    }
    for (final type in [
      'Audio',
      'MusicAlbum',
      'MusicArtist',
      'AudioBook',
      'Book',
      'Photo',
      'PhotoAlbum',
      'Game',
      'Program',
      'LiveTvChannel',
      'Playlist',
    ]) {
      expect(AppFeatures.allowsItem(type), isFalse, reason: type);
    }
    for (final type in [
      'music',
      'books',
      'audiobooks',
      'photos',
      'games',
      'livetv',
    ]) {
      expect(AppFeatures.allowsLibrary(type), isFalse, reason: type);
    }
  });
}
