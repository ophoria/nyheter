# Nyheter

A calm news board for your Mac's screen saver. When the Mac rests, Nyheter shows the latest
headlines one story at a time, big and easy to read. The companion app is the remote control:
choose sources, order, timing, filters and theme, with a live preview.

Written in Swift with AppKit, SwiftUI and Core Animation. It has no dependencies and builds with a single script.

## Features

- **Sources:** SVT Nyheter, Sveriges Radio (Ekot), Dagens Nyheter, SCB, The New York Times,
  BBC News, MS NOW and Reuters, each with its own feeds (for example World, Sport or SVT's regional news).
  Reuters has no RSS of its own any more, so its feeds are Google News searches limited to reuters.com
  (headlines only).
- **Your own feeds:** paste the address of any RSS, Atom or JSON feed, or of a website that announces
  one, and it becomes a source of its own.
- **Fresh news first:** stories older than a chosen age are skipped. New stories, and stories that mention
  one of your watchwords, go first with a pulsing mark. Stories the screen saver hasn't shown before come
  before ones it has (it remembers a week).
- **Right-hand column:** a QR code to the story on the source's site, to read on your phone, and the next stories in line. Each can be switched off.
- **Order:** take turns between sources in a pattern you choose, or show them in order.
- **Timing:** a fixed time per story, or adapted to the length of the text.
- **Themes:** Morning Paper, Morning Paper Photo, Night Desk, Svea, Swiss, Pastel, Matrix,
  Shelter and Terminal. A random theme can be picked each time the screen saver starts.
- **Filters:** hide stories by word or regular expression, or hide whole sections. A searchable
  log shows what was filtered and why.
- **The world right now:** every few stories, optional live counters (world population, births
  and deaths today, CO₂ emissions and more), estimated from published yearly figures.
- **Offline-friendly:** the last fetch is saved. A new start shows it at once and only fetches
  again when it is older than the refresh interval. Stories appear as each feed answers.
- **17 languages** for the interface, following the macOS language or chosen in the app.
- **Burn-in protection:** the layout drifts slightly every minute.

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools (`xcode-select --install`) to build

## Build and install

```sh
./build.sh            # builds build/Nyheter.app (screen saver inside) and build/Nyheter.zip
./build.sh install    # also copies the app to /Applications and installs the screen saver
```

Then open **System Settings › Screen Saver** (on macOS 26, **Wallpaper › Screen Saver…**) and
choose **Nyheter**. The app's **Install the screen saver** button does the same as `install`.

By default the build is ad-hoc signed, so on another Mac macOS asks you to allow it under
**System Settings › Privacy & Security**. With an Apple Developer account, set `SIGN_ID` and
`NOTARY_PROFILE` (see `build.sh`) to sign and notarize.

### macOS's large clock

macOS draws a large clock over every screen saver. Nyheter can't remove it, but you can: the
app's **Clock…** button opens the right settings page (Lock Screen on macOS 14–15, Wallpaper ›
Clock Appearance… on macOS 26). Set **Show large clock** to **On Lock Screen** or **Never**.

## Project layout

| Path | What it is |
|---|---|
| `Shared/` | Shared by the app and the screen saver: rendering (`NewsCanvas`), themes, sources and feed parsers, filters, settings, saved news, shown stories (`SeenStories`) |
| `Saver/` | The thin `ScreenSaverView` wrapper |
| `App/` | The settings app (SwiftUI) with live preview |
| `Resources/l10n/` | Translations, one `.lproj` per language (see its README) |
| `Resources/lucide/` | Bundled [Lucide](https://lucide.dev) icons (ISC licence) |
| `tools/` | Translation checker, offscreen render harness, icon generator |

## Development

```sh
./build.sh snapshots        # renders every theme offscreen to build/snapshots
python3 tools/check-l10n.py # checks every translation against English
```

Settings live in `~/Library/Application Support/Nyheter/`. The screen saver runs sandboxed and
writes its own files (filter log, saved news, shown stories) inside its container. The app reads both.

## Privacy

Nyheter fetches the public RSS/Atom feeds of the sources you turn on, directly from those sites
(for Reuters, from Google News).
There are no accounts, analytics or servers of its own.

News content and photos belong to their publishers.
