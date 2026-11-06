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

## Video stickers, clips and GIFs on macOS

The "Demo video stickers" pack (WebM, MP4 and GIF; see
`assets/video_stickers/README.md`) plays through `video_native`, whose build
hook needs the FFmpeg prefix built by
`packages/video_native/native/recipe/build.sh` (macOS arm64 only so far).
Without it, or on another platform, the build still succeeds and the app
runs: it logs once that video stickers are off and those items keep their
placeholder. The web does not play video yet.
