# Media client fork

Personal Google TV and Samsung Tizen client based on [Moonfin 3.0.0](https://github.com/Moonfin-Client/Moonfin-Core/releases/tag/3.0.0) (`eb43b626f`). Development lives on the `media` branch; `upstream` points to Moonfin-Client/Moonfin-Core.

This fork is a minimal video client. Its navigation is **Search, Home, Retro TV, Genres, Favourites and Libraries**. It retains movies, series, seasons, episodes, video collections, people, trailers, sign-in and connection recovery. Live TV/DVR, Seerr, SyncPlay, music, audiobooks, books/comics, photos, games, downloads, casting, achievements, friends/chat and server messages are omitted. Application Settings, administration and playlists are also hidden. Existing server data and saved preferences are preserved; they cannot re-enable omitted features.

The Apple TV app’s tvOS 26 guide screens are the visual baseline, with Media’s styling references in `../media/web/src/style.css`, `scroll-fade.jsx` and `motion/motion.css`. Home uses full-bleed artwork and landscape rails; video Library uses a category panel and six-column poster grid; details put the synopsis and actions on the left and credits on the right. Purchasing and Family Sharing are omitted. TV browsing uses this presentation regardless of saved layout or theme preferences.

Shared colours, spacing, radii and focus geometry live in `packages/design/lib/src/theme/tv_tokens.dart`; timing lives in `AppMotion`. The components in `lib/ui/tv/` own pill buttons, concentric focus frames, browse headers, status views, modal panels and menu rows, pause information and reveal transitions. Typography uses bundled Inter under the SIL Open Font License. Screen/content entrances, artwork and dialogs share fade/blur motion and respect reduced motion. The Windows native HDR player keeps its separate transparent composition path.

Startup uses the shared animated CRT-style loading glow on black. Home reveals navigation and content together after its first rows, banner response and decoded artwork are ready; a five-second artwork timeout releases a stalled page. Refreshes preserve visible content. Scroll edges mask content to transparency. Detail pages expose Back from the action row, offer a remote-scrollable full synopsis, merge repeated cast credits and omit Chapters. Playback retains local transport, episode selection, audio/subtitle controls and quality/information menus. Feature policy lives in `lib/config/app_features.dart` and applies to navigation, catalogue queries, actions and startup services. Losing connectivity shows request recovery rather than switching to the omitted downloads catalogue. The TV screensaver uses library artwork and a clock, with shared reveal motion.

The browser preview exercises the shared TV UI. Android/Google TV and native Samsung Tizen have had sampled hardware playback and Retro remote-control checks, not full platform certification. A viewer confirmed English subtitle timing in current Chromecast Retro playback and a Batman Begins preview-path seek/reopen test; the historical intermittent desynchronization was not reproduced. Native Mac and the separate native Apple player remain unverified; browser checks do not establish native playback, HDR or performance.

## Local TV preview on macOS

Install Flutter 3.47 or newer. The primary styling loop runs the real app's TV UI in a local browser, without Xcode or an Apple account:

```sh
flutter pub get
./run-tv-preview.sh
```

Once Flutter reports ready, open <http://127.0.0.1:8788/> in Chrome and sign into your Jellyfin server. The address stays fixed so browser-local login and preferences survive server restarts. Use arrow keys to navigate, Enter to select, and Escape to go back. In the running terminal, press `r` for hot reload, `R` for hot restart, and `q` to quit. The server listens on loopback only.

Run the full root suite with `flutter test --no-pub`. For a focused TV browsing regression, use:

```sh
flutter test --no-pub \
  test/ui/flows/tv_browsing_flow_test.dart \
  test/ui/screens/home/tv_home_content_test.dart \
  test/ui/widgets/startup_loading_test.dart \
  test/data/services/connectivity_service_test.dart
```

The journey uses the production router, screens, detail/library models, and Jellyfin API parser with controlled feed/HTTP/artwork inputs. It drives arrows and Enter through Home, movie actions, More cancellation, credits, Similar titles, library cards and categories, library switching, Search keyboard open/close, Genres → scoped results/return, delayed movie responses, Favorites add/remove and return, and absence of Settings in navigation and direct-route redirects. TV key tests reproduce browser scroll shortcuts and focus parked at the root; cast layout checks cover wrapped names and larger text. The Favorites flow holds a removal response until after the detail page closes, checks the empty-state exit, and verifies the Home heart updates. Model checks cover removal, shifted paging offsets, refilling an emptied page, and leaving before the first response. It checks focus restoration and fails on unexpected API calls or framework exceptions at each step. Separate cold-load tests cover both response orders, delayed/stalled artwork, background refresh, empty/error feeds, and loading-indicator geometry at multiple sizes and pixel densities. The connectivity regression checks that an initial network result leaves session services alone until an active client exists, then verifies that the client handoff still starts reconnect/sync. These checks do not cover sign-in, actual video playback or physical remotes.

For an optional native Mac preview, install full Xcode and CocoaPods, then run `./run-macos-tv.sh`. TV mode uses the fixed shared presentation. The macOS Debug target is configured for ad-hoc signing and a separate preview bundle ID, but its native build has not been verified. Apple's direct Xcode downloads and the App Store currently require an Apple account.

Browser preview validates shared UI and navigation. Its player and renderer differ from native TV backends; each release needs platform-specific playback and remote checks.

## Native Samsung TV prototype

The native Tizen 6.5 / ARM build reuses this client's TV interface and Retro TV
logic with Samsung's native Media Player through `video_player_videohole`.
Run `./build-tizen.sh` to produce
`build/tizen/tpk/org.media.tizen-3.0.0.tpk`; the script only builds locally.
The ignored `build-tizen.private.env` supplies local SDK paths and the signing
profile through the build script's existing settings. Keep certificates and
device addresses outside versioned source. This is a native Flutter/CAPI player,
not a web/AVPlay wrapper. It uses one decoder and explicitly seeks before play.
SRT/VTT and PGS overlays support subtitle delay; audio delay is unsupported.
PGS loads asynchronously and cannot use text appearance controls. ASS and other
unsupported subtitle formats use server rendering. Uncached PGS startup latency,
HDR, surround routing, crop/stretch and sustained surfing need device-specific
verification; a build or Flutter capture does not prove hardware picture quality.

Retro TV reuses normal audio/subtitle controls while retaining scheduled channel
positions and preview watch-history semantics. Open Options with OK or Right to
choose Audio or Subtitles. Subtitle timing opens above the caption region and
offers earlier/later steps and Reset; available controls follow the active backend.
See
[Retro TV programming](RETRO_TV_PROGRAMMING.md).

---

<h1 align="center">Moonfin</h1>
<h3 align="center">Premium Jellyfin, Emby & Plex client for mobile, tablet, desktop, TV, and web</h3>

---
<p align="center">
  <img width="1920" height="1080" alt="moonfin_1920x1080" src="https://github.com/user-attachments/assets/b1d9c7d8-f113-457d-ab5c-1600bbd0600a" />
</p>


[![License](https://img.shields.io/github/license/Moonfin-Client/Moonfin-Core.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Moonfin-Client/Moonfin-Core)](https://github.com/Moonfin-Client/Moonfin-Core/releases)
[![Github Downloads](https://img.shields.io/github/downloads/Moonfin-Client/Moonfin-Core/total?label=Downloads)](https://github.com/Moonfin-Client/Moonfin-Core/releases) 
[![Google Play Downloads](https://playbadges.pavi2410.com/badge/downloads?id=org.moonfin.androidtv&pretty)](https://play.google.com/store/apps/details?id=org.moonfin.androidtv)
[![BuyMeACoffee](https://raw.githubusercontent.com/pachadotdev/buymeacoffee-badges/main/bmc-yellow.svg)](https://www.buymeacoffee.com/moonfin)
[![Discord](https://img.shields.io/badge/Discord-Join%20Us-5865F2?logo=discord&logoColor=white)](https://discord.gg/moonfin)

> **[← Back to main Moonfin project](https://github.com/Moonfin-Client)**

Moonfin is a media client for Jellyfin, Emby, and Plex servers, built with Flutter. One shared codebase powers phones and tablets, Windows, macOS, and Linux, Android TV, Fire TV, and Apple TV, and the browser. It's made for people who want a modern, customizable experience on every screen they own.

## Where to get it

| Platform            | Download                                                                                                                                                                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Android Mobile / TV | [![Google Play](https://img.shields.io/badge/Google%20Play-grey?logo=Google+Play\&label=)](https://play.google.com/store/apps/details?id=org.moonfin.androidtv)                                                                                                                                |
| Fire TV             | [![Amazon Appstore](https://img.shields.io/badge/Amazon%20Appstore-FF9900?logo=amazon\&logoColor=white)](https://www.amazon.com/Moonfin/dp/B0H76BG3DW)                                                                                                                                         |
| iOS                 | [![App Store](https://img.shields.io/badge/App_Store-0D96F6?logo=app-store\&logoColor=white)](https://apps.apple.com/app/moonfin/id6761283970)                                                                                                                                                 |
| Linux               | [![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux\&logoColor=fff)](https://aur.archlinux.org/packages/moonfin-bin)<br>[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux\&logoColor=black)](https://github.com/Moonfin-Client/Moonfin-Core/releases) |
| macOS               | [![App Store](https://img.shields.io/badge/App_Store-0D96F6?logo=app-store\&logoColor=white)](https://apps.apple.com/app/moonfin/id6761283970)<br>[![Homebrew](https://img.shields.io/badge/Homebrew-FBB040?logo=homebrew\&logoColor=fff)](https://formulae.brew.sh/cask/moonfin)              |
| tvOS                | [![App Store](https://img.shields.io/badge/App_Store-0D96F6?logo=app-store\&logoColor=white)](https://apps.apple.com/app/moonfin/id6761283970)                                                                                                                                                 |
| Windows | [![Release](https://img.shields.io/github/v/release/Moonfin-Client/Moonfin-Core?label=Release&logo=github&logoColor=white)](https://github.com/Moonfin-Client/Moonfin-Core/releases)<br>[![WinGet](https://img.shields.io/winget/v/Moonfin.Moonfin?label=WinGet&logo=windows&logoColor=white)](https://winstall.app/apps/Moonfin.Moonfin)<br>or `winget install Moonfin.Moonfin` |                                                                                                     |

## Supported Servers

| Server | Minimum Version | Status |
|--------|------------------|--------|
| Jellyfin | 10.8.0+ | Full support |
| Emby | 4.8.0.0+ | Full support (the admin panel needs 4.9+) |
| Plex | Plex Media Server 1.43+ | Supported, without the features that need the Moonbase plugin |

## Platform Support

| Platform | Minimum Version | Status |
|----------|------------------|--------|
| **Android** | 7.0 (API 24) | Full support |
| **Android TV / Google TV** | Android 7.0 (API 24) | Full support |
| **Fire TV** | Fire OS 6 | Full support |
| **iOS** | 18.0 | Full support |
| **Apple TV (tvOS)** | 18.0 | Full support |
| **macOS** | 15.0 (Sequoia) | Full support |
| **Windows** | 10 (x64 and ARM64) | Full support |
| **Linux** | GTK 3+, CMake 3.13+ | Full support (Wayland and X11) |
| **Web** | Modern browsers (installable PWA) | Full support |

> Android TV, Fire TV, and Apple TV ship from this same codebase with a TV-tuned interface and D-pad navigation. Fire TV runs the same native backend as Android TV. Web runs as an installable PWA through the Moonbase server plugin.

## Upstream features

The following documentation describes upstream Moonfin, including features omitted from this fork. Upstream store downloads do not contain this fork’s changes.


- **One codebase, every screen.** Phones, tablets, desktop, Android TV, Apple TV, and web, with navigation tuned for touch, pointer, and remote.
- **Playback that just works.** Wide codec support including AV1, HEVC, Dolby Vision, Dolby Atmos, HDR10+, and audio passthrough. Dolby Vision Profile 7 direct plays on Apple and Android TV, converted in real time instead of transcoded, with both layers of FEL files on Apple devices, and Windows can send HDR to the display untouched. Two subtitle tracks can show at once on every player. See [Playback and Codecs](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Playback-and-Codecs).
- **A mini player on desktop** that keeps the video playing in a bar along the bottom while you browse.
- **Offline downloads** in original or smaller server-transcoded quality, with automatic folder organization, offline subtitles, automatic downloads of new episodes for the series you follow, and Smart downloads on phones and tablets that keep the next episodes of a show downloaded and clear them once watched. See [Downloads](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Downloads).
- **Ebooks and audiobooks.** Read EPUB, MOBI, AZW/AZW3, PDF, and comic archives, with your reading progress synced to the server. Play M4B audiobooks with chapter navigation.
- **Retro games** browsed and played in-app from a server game library, with gamepad support, save states and battery saves that sync between devices, hardware rendering on Android, and RomM-backed libraries you browse with your own RomM account. See [Retro Games](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Retro-Games).
- **Multi-server unified library** that merges several Jellyfin and Emby servers into one browsable, searchable UI.
- **Library styles** for video, music, and book libraries, from the classic grid to a docked side panel, an immersive music hero, or a bookstore shelf.
- **A setup wizard on first run** that asks how you want the app to look, with live previews built from your own artwork.
- **Five detail screen styles** to pick from: Classic, Modern, Spotlight, Nouveau, and Minimalist.
- **Featured media bar** with six layouts, plus optional in-bar trailer previews.
- **Themes and a Theme Store** with a built-in editor, server-side sync, and an OLED mode for true blacks, plus custom loading animations and a screensaver on TV.
- **An integrated admin panel** for Jellyfin and Emby, covering settings, users, libraries, Live TV, logs, devices, and analytics, plus a messages window for notes from your server admin.
- **Discovery with Seerr** built into the details screen, with trending, popular, and upcoming rows and request status overlays.
- **Live TV and DVR** with a program guide, rewind on channels that keep a rewind window, a quick channel changer on TV, automatic recovery when a channel stalls, and recording management.
- **Client certificates (mTLS)** for servers that require one, with a page you open on your phone to send the certificate to a TV.
- **Trickplay scrubbing** as a single thumbnail, a filmstrip, or full screen, on both Jellyfin and Emby.
- **Cinema Mode and segment skipping** for pre-rolls, intros, credits, and SponsorBlock.
- **Casting and remote control** over Google Cast, DLNA, and AirPlay, plus control of other Jellyfin devices on your network with a D-pad and search typed from your phone. Other Jellyfin apps can steer Moonfin too.
- **SyncPlay** for synchronized group watching.
- **Personal ratings** as a like, five stars, or a score out of ten, usable to sort or filter a library.
- **Kids Mode** that strips the app back to what a child needs and locks the way out with a PIN, plus blocked ratings that apply everywhere in the app.
- **Achievement Badges** drawn natively when your Jellyfin server runs the Achievement Badges plugin, including its friends list and chat.
- **Anime markers** for filler, recap, canon, and subbed or dubbed episodes, served by the Moonbase plugin.
- **Ratings from MDBList and TMDB**, home row customization with a seasonal holiday row, and in-app update checks.

The full list is on the [Features](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Features) wiki page.

## Screenshots

### TV and desktop

<p align="center">
  <img src="assets/images/tv/1-home.png" width="100%" alt="Home screen with the featured media bar" />
</p>
<p align="center">
  <img src="assets/images/tv/2-playback.png" width="49%" alt="Player with trickplay thumbnails and the subtitle menu" />
  <img src="assets/images/tv/5-livetv.png" width="49%" alt="Live TV guide, channel changer and player" />
</p>
<p align="center">
  <img src="assets/images/tv/3-details.png" width="49%" alt="The five detail screen styles" />
  <img src="assets/images/tv/4-mediabars.png" width="49%" alt="The six media bar styles" />
</p>
<p align="center">
  <img src="assets/images/tv/8-home-rows.png" width="49%" alt="Modern and Classic home rows" />
  <img src="assets/images/tv/6-navigation.png" width="49%" alt="Top and Sidebar navigation" />
</p>
<p align="center">
  <img src="assets/images/tv/7-books-games.png" width="49%" alt="Books library and retro game library" />
  <img src="assets/images/tv/9-music.png" width="49%" alt="Music player with synced lyrics" />
</p>

### Mobile

<p align="center">
  <img src="assets/images/phone/1-home.png" width="24%" alt="Phone home screen with the featured media bar" />
  <img src="assets/images/phone/2-playback.png" width="24%" alt="Phone player with trickplay and the subtitle menu" />
  <img src="assets/images/phone/3-details.png" width="24%" alt="The five detail screen styles on a phone" />
  <img src="assets/images/phone/4-mediabars.png" width="24%" alt="The six media bar styles on a phone" />
</p>
<p align="center">
  <img src="assets/images/phone/7-navigation.png" width="24%" alt="Top, Sidebar and Bottom navigation on a phone" />
  <img src="assets/images/phone/5-livetv.png" width="24%" alt="Phone Live TV guide and player" />
  <img src="assets/images/phone/6-books-games.png" width="24%" alt="Phone books and retro game libraries" />
  <img src="assets/images/phone/8-music.png" width="24%" alt="Phone music player with synced lyrics" />
</p>

## Installation

The store links above are the easy route. To install a file yourself, download it from the [Releases page](https://github.com/Moonfin-Client/Moonfin-Core/releases) and pick the one for your device:

| Platform | File |
|---|---|
| Android (phones and tablets) | `Moonfin_Android_v<version>.apk` |
| Android TV / Google TV / Fire TV | `Moonfin_AndroidTV_v<version>.apk` |
| iOS | `Moonfin_iOS_v<version>_unsigned.ipa` (for self-signing) |
| Apple TV | `Moonfin_tvOS_v<version>_unsigned.ipa` (for self-signing) |
| Windows x64 | `Moonfin_Windows_v<version>.exe` |
| Windows ARM64 | `Moonfin_WindowsARM64_v<version>.exe` |
| macOS | `Moonfin_macOS_v<version>.dmg` |
| Linux x64 | `Moonfin_Linux_v<version>.<ext>` (AppImage, deb, rpm, snap, flatpak, tarball) |
| Linux ARM64 | `Moonfin_LinuxARM64_v<version>.<ext>` (same formats) |
| Web | Served as a PWA by the [Moonbase](https://github.com/Moonfin-Client/Plugin) server plugin, no download needed |

On Arch Linux, install from the AUR with `yay -S moonfin-bin` (or `paru -S moonfin-bin`, `pamac build moonfin-bin`).

Click-by-click steps for every platform are on [Installation](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Installation), and [Getting Started](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Getting-Started) covers connecting to your server for the first time.

## Building

Flutter stable 3.47 or newer is the one thing every platform needs (Dart 3.13 comes with it). Each target also needs its own toolchain: Android Studio with the SDK and NDK for Android, Xcode and CocoaPods for iOS and macOS, the flutter-tvos toolchain for Apple TV, Visual Studio and vcpkg for Windows, and a handful of development packages on Linux. Every Android command also takes a `--flavor`.

```bash
git clone https://github.com/Moonfin-Client/Moonfin-Core.git
cd Moonfin-Core
flutter pub get
```

The per-platform build commands are on [Building from Source](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Building-from-Source).

## Documentation

The deeper reference material lives in the [Wiki](https://github.com/Moonfin-Client/Moonfin-Core/wiki):

| Page | What it covers |
|------|----------------|
| [Features](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Features) | The full feature list, section by section |
| [Playback and Codecs](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Playback-and-Codecs) | The backend per platform, the codec table, HDR, and audio passthrough |
| [Downloads](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Downloads) | Original and transcoded downloads, quality presets, and storage paths |
| [Retro Games](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Retro-Games) | Playing server game libraries in-app, cores, controllers, and save states |
| [Installation](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Installation) | App store links first, then installing a release file by hand on every platform, and how updates work |
| [Getting Started](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Getting-Started) | Connecting to your server, Quick Connect, the setup wizard, and the settings worth a look on day one |
| [User Guide](https://github.com/Moonfin-Client/Moonfin-Core/wiki/User-Guide) | The player on touch, remote and keyboard, Live TV, casting and remote control, Seerr requests, downloads, subtitle downloads, themes, parental controls, and Kids Mode |
| [Common Problems](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Common-Problems) | Plain fixes for connection, login, playback, sound, subtitle, download and casting trouble |
| [Collecting Logs](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Collecting-Logs) | Capturing a diagnostic report for a bug report |
| [Custom mpv Configuration](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Custom-mpv-Configuration) | Tuning playback with your own `mpv.conf`, allowed options, and SVP on Windows |
| [Building from Source](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Building-from-Source) | Toolchain versions, step by step setup, and the build commands for every platform |
| [Development](https://github.com/Moonfin-Client/Moonfin-Core/wiki/Development) | Developer notes, contributing guidelines, and the pull request process |

## Contributing

Contributions are welcome. Check the existing issues first, discuss major feature changes before implementing them, match the existing code style, run `flutter analyze`, and test on at least one target platform. Keep pull requests focused and include context, screenshots or logs where useful.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guidelines and the pull request process.

## Help translate Moonfin [here](https://translate.moonfin.io/projects/moonfin/moonfin-core/)

<a href="https://translate.moonfin.io/projects/moonfin/moonfin-core/">
  <img
    src="https://translate.moonfin.io/widget/moonfin/moonfin-core/multi-auto.svg"
    alt="Moonfin Core translation status by language"
  />
</a>

## Support and Community

- **Issues**: [GitHub Issues](https://github.com/Moonfin-Client/Moonfin-Core/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Moonfin-Client/Moonfin-Core/discussions)
- **Discord**: [Discord](https://discord.gg/moonfin)
- **Upstream Jellyfin**: [jellyfin.org](https://jellyfin.org)

## Credits

Moonfin is built on the work of:
- **[Jellyfin Project](https://jellyfin.org)**
- **Jellyfin client contributors**
- **Moonfin contributors**
- **[MakD](https://github.com/MakD)** - Original Jellyfin-Media-Bar concept that inspired our featured media bar
- **[MediaLyze](https://github.com/frederikemmer/MediaLyze)** The Admin analytics UI was inspired by this open-source project 

## License

Moonfin is free software. You can redistribute it and modify it under the terms
of the GNU General Public License as published by the Free Software Foundation,
either version 2 of the License or, at your option, any later version. See
[LICENSE](LICENSE) for the version 2 text.

---

<p align="center">
  <strong>Moonfin</strong> is an independent project and is not affiliated with the Jellyfin or Emby projects.<br>
  <a href="https://github.com/Moonfin-Client">← Back to main Moonfin project</a>
</p>
