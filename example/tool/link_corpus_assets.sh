#!/usr/bin/env bash
# Copies a local corpus of Lottie stickers into the example's asset folder as
# `<pack>--<n>.json` or `<pack>--<n>.tgs` (gzipped), where CorpusStickerPack
# finds them. The files stay out of
# git (assets/sticker_corpus/.gitignore): they are third-party property.
#
#   example/tool/link_corpus_assets.sh /path/to/sticker-corpus
#
# The argument: a folder with one subfolder per pack, each holding
# `*.json` or `*.tgs` Lottie files, or `*.webp` still stickers. Run it again to refresh; it replaces earlier copies.
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "usage: $0 <corpus directory with one folder per pack>" >&2
  exit 2
fi

corpus="$1"
dest="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/sticker_corpus"

# Only copies made by an earlier run are removed.
find "$dest" -maxdepth 1 \( -name '*--*.json' -o -name '*--*.tgs' -o -name '*--*.webp' \) -delete

count=0
for pack in "$corpus"/*/; do
  name="$(basename "$pack")"
  for file in "$pack"*.json "$pack"*.tgs "$pack"*.webp; do
    [[ -e "$file" ]] || continue
    cp "$file" "$dest/${name}--$(basename "$file")"
    count=$((count + 1))
  done
done

echo "copied $count stickers into $dest"
echo "rebuild the app to bundle them (a hot reload does not)."
