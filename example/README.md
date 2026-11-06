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

**What has been run.** `flutter build web --release` (with and without the
folder) and `flutter build web --wasm` compile. The protocol runs on the VM in
tests over an in-memory worker. **No browser has run the page: the real worker,
the wasm and the Dart client together are unrun.**
