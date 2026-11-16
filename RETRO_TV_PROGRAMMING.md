# Retro TV programming

The client imports the Media project's authored categories from the Windows
`data/moonfin/home-rotation-config.json`, plus reviewed collections from
`media/discovery_collections.json`. The bundled snapshot is
`assets/programming/media_categories.json`. Update it from this checkout with:

```sh
python3 tool/sync_retro_tv_categories.py --source-file /path/to/category-export.json
```

For a read-only Windows export, supply `--host` and `--remote-config` instead
of `--source-file`. The SSH host and absolute configuration path must be explicit.
The helper writes the local asset; it does not change
Jellyfin collections, Media home rows, server settings, or installed TV apps.
Existing category channel numbers are retained when new definitions are imported.
The snapshot is updated explicitly; it is not a live dependency on the Media web app.

## Scheduling rules

- The catalog loads every movie, series and episode page. Series metadata supplies
  inherited TV genres and ratings; episode runtime remains episode-specific.
- Categories use complete matching pools, independent of the home row display limit.
- Alternate movie copies and episode copies share canonical programming identities.
- No overlapping airings of the same film or series anywhere in the lineup.
- No consecutive identical films or episodes on a channel.
- Each admitted movie channel reserves two distinct fallback films; a TV channel
  reserves a series with at least two episodes. Remaining titles can be shared
  across matching categories when they are free to air.
- Unused and least-recently-aired titles/series lead selection. TV chooses the series
  first, then advances through its episode order. Long series do not gain more
  selection weight merely by having more episodes.
- Small film themes are omitted as permanent channels. Small franchises feed one
  deeper Franchise Spotlight pool. Four eligible director channels are chosen when
  a new lineup is built; a restored lineup keeps its director identities.
- Movie-channel capacity uses available movie hours (roughly 16 library hours per
  channel). This is a diversity budget, not a promise of a 16-hour rerun cooldown.
  Rerun spacing depends on each category's depth and competing eligible channels.

The rolling schedule keeps 24 hours ahead and seven days of recent airings. Local
storage is scoped to the signed-in server/account. Compact programming metadata,
reservations and item-ID/time slots persist across reloads. It does not store stream
URLs, authentication tokens, personal playback progress, paths or the full cast.
A cached catalog can start playback immediately; catalog refreshes run after six
hours. Surfing continues to use preview playback; only choosing intentional viewing
commits personal watch progress.

## Verification

```sh
flutter test --no-pub test/ui/screens/playback/retro_channel_test.dart
flutter test --no-pub test/ui/widgets/retro_tv_flow_test.dart
```

The optional full-library simulation reads a private, read-only JSON export with
`movies`, `shows`, and `episodes` arrays of Jellyfin item DTOs. Keep it outside the
repository. It opens no streams and performs no server writes:

```sh
flutter test --no-pub test/ui/screens/playback/retro_programming_simulation_test.dart \
  --dart-define=RETRO_TV_LIBRARY_FIXTURE=/absolute/path/to/catalog.json
```

It checks a simulated week under three random seeds: continuous Now/Next slots,
24-hour lookahead, category membership, overlapping movies/series, consecutive
repeats, library coverage, and measured rerun gaps. Browser playback, remote-key
navigation and reload continuity must also be checked before a TV rollout.
