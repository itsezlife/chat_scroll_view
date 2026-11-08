# Telegram stickers (local only)

The Lottie stickers a maintainer keeps on their machine to try the Lottie
pipeline on real artwork (`CorpusStickerPack`). **They are Telegram's
property.** They are never committed, never copied into tests, goldens or
docs, and this folder's `.gitignore` ignores everything but this README and
itself, so a stray `git add` cannot take them.

A checkout without the files builds and runs as usual: the stickers page just
lists the recent stickers (and says it has none when there are none).

## Putting them here

The corpus is one folder per pack, each with `0.json`, `1.json`, ...:

```
<corpus>/baby_yoda/0.json
<corpus>/duck/3.json
```

A pubspec asset folder is not recursive, and listing a pack folder that is
absent in a checkout would fail `flutter build`, so the files live flat here,
named `<pack>--<n>.json`. The script does the copy:

```sh
example/tool/link_corpus_assets.sh \
  /Users/gothiq2302/Documents/VSCodeProjects/Flutter/chat_scroll_view/.scratch/native-media-ffi/corpus/telegram-stickers
```

or by hand, for every pack folder:

```sh
cd example/assets/sticker_corpus
for pack in "$CORPUS"/*/; do
  name=$(basename "$pack")
  for f in "$pack"*.json; do cp "$f" "${name}--$(basename "$f")"; done
done
```

Rebuild the app afterwards (a hot reload does not re-read the asset manifest).
Check that nothing is staged: `git status` must show nothing under this
folder, and `git check-ignore -v example/assets/sticker_corpus/duck--0.json`
names the rule above.

## Desktop without copying

On macOS and the other desktop targets the same folders can be read in place:

```sh
flutter run --dart-define=CHAT_CORPUS_DIR=/path/to/telegram-stickers
```

A folder found there takes over the bundled pack of the same name.
