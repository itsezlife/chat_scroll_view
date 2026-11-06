# chat_scroll_view example

Demo chat app for the `chat_scroll_view` package: composer, selection, new-message
pill, and either the offline comments dataset or the local Supabase backend.

```sh
# from repo root
./scripts/dev.sh
cd example
flutter run --dart-define-from-file=../config/development.supabase.json
```

## Lottie stickers on the web

The Lottie stickers play on the web through a WebAssembly build of the native
library in a worker. The built files are not committed (where a host serves
them from is an open question); build them into `example/web/lottie/`, which
is gitignored, before `flutter build web`:

```sh
dart packages/lottie_native/native/tool/build_web.dart --out example/web/lottie
```

This needs `cargo` and the Rust target `wasm32-unknown-unknown`; nothing is
installed for you. Without the folder the build still succeeds and the app
runs: it logs once that Lottie stickers are off and those stickers keep their
placeholder. Frames are kept in memory only on the web.

What has and has not run in a browser: see "Not run" under Web in
[host integration](../docs/host-integration.md).

## Stickers and GIFs in the panel

The panel lists only real content:

- the emoji page: the emoji catalogue, then the animated emoji pack (custom
  emoji, not stickers);
- the stickers page: the recent stickers, then the local Telegram corpus, a
  pack per folder (see "Local Telegram stickers" below). Without the corpus
  (a fresh checkout, CI) it lists the recents alone, and with no recents
  either it says "Стикеров пока нет" (`PanelStrings.stickersEmpty`);
- the GIF page: the recent GIFs, then Giphy's trending and search (see
  "Giphy GIFs" below). Without a key it lists the recents alone, and with no
  recents either it says "GIF не найдены" (`PanelStrings.gifsEmpty`).

The bundled demo packs (Lottie, static and video stickers, MP4 clips and
GIFs) are no longer on any panel page: they stay in the app for the showcase
chat, which shows every one of them, and one already in the recents stays
listed there. Tapping a sticker or GIF sends it as a message
and leaves the panel open; a sent sticker or GIF cannot be edited. Wiring:
`lib/src/app/app_services.dart` (the page sources) and
`lib/src/features/chat/input/media_panel_pages.dart`.

## Giphy GIFs on the GIF page

With a Giphy API key the GIF page lists Giphy's trending GIFs (paged as you
scroll), gets a search field in the panel's bottom bar, and shows "Powered by
GIPHY" at the top of the list, as Giphy's terms ask. Without a key nothing is
sent anywhere: the page lists the recent GIFs alone (or says it has none),
has no search, and the app logs once that Giphy is off. Get a key from the
Giphy developer dashboard (developers.giphy.com, an API app).

```sh
flutter run --dart-define=GIPHY_API_KEY=<your key>
# or keep the key in a file that is not committed
# (`config/*.local.json` style, already your own habit) and:
flutter run --dart-define-from-file=<that file>   # {"GIPHY_API_KEY": "..."}
```

The key is read once, from `String.fromEnvironment`, and handed to the Giphy
client; it is never logged and never part of an error message. Never commit
it. Clips play from Giphy's MP4 renditions through the video decoder, so
they need the native video library (see below); without it they keep their
placeholder.

A tapped GIF is sent as a lone document, `![title](document:giphy:<id>)`: the
message carries Giphy's id, not a URL. The chat draws it by asking Giphy for
that id (one batched request for the ids it does not know) and downloading
the file through the asset pipeline, so a message from the backend chat still
plays after a restart. The offline-only generated chat does not keep
messages. Recent GIFs are remembered by key, but are listed again only once
the session has seen the clip (after a restart, once it is in trending or a
search); a clip listed only in the recents stays out until then.

Offline or with a busy server the page shows "Couldn't load GIFs" with a
retry button under the recent GIFs; there are no demo clips beneath it.

## Local Telegram stickers (not in the repository)

A maintainer's local corpus of Lottie stickers (one folder per pack) can be
tried on the stickers page, one pack per folder. **The files are Telegram's
property: they are never copied into the repository, tests, goldens or docs.**
`assets/telegram_stickers/` holds only a README and a `.gitignore` that
ignores everything else; the pubspec lists that folder, so a checkout without
the files builds and runs as before.

```sh
# copy the corpus into the git-ignored asset folder (every platform):
example/tool/link_corpus_assets.sh <corpus>/telegram-stickers
# rebuild: assets are bundled at build time

# or, on desktop only, read the folders in place:
flutter run --dart-define=CHAT_CORPUS_DIR=<corpus>/telegram-stickers
```

On Android and iOS use the first: no device file access or new dependency is
needed since the files ship inside the app bundle. See
`assets/telegram_stickers/README.md`.

## Video stickers, clips and GIFs on macOS

The "Demo video stickers" pack (WebM, MP4 and GIF; see
`assets/video_stickers/README.md`) plays through `video_native`, whose build
hook needs the FFmpeg prefix built by
`packages/video_native/native/recipe/build.sh` (macOS arm64 only so far).
Without it, or on another platform, the build still succeeds and the app
runs: it logs once that video stickers are off and those items keep their
placeholder. The web does not play video yet.
