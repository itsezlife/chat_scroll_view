# Media photos

Eight JPEG pictures for the demo chat's media messages (`DemoPhotos`): one
frame each of a synthetic FFmpeg gradient, so there is no third-party
artwork here. Their proportions differ (3:2, 2:3, square, a panorama, a tall
strip, a small one, 4:3, 4:5), so single boxes and albums lay out every
shape.

| File | Size |
| --- | --- |
| `harbour.jpg` | 1280 x 853 |
| `cliff.jpg` | 720 x 1080 |
| `meadow.jpg` | 900 x 900 |
| `skyline.jpg` | 1600 x 600 |
| `tower.jpg` | 500 x 1400 |
| `pebble.jpg` | 240 x 180 |
| `dunes.jpg` | 1200 x 900 |
| `lagoon.jpg` | 1080 x 1350 |

## Regenerating

Needs the FFmpeg at `/opt/homebrew/bin/ffmpeg`. Save the script below as
`gen.sh` and run `bash gen.sh <this directory>`; then update the byte sizes
in `DemoPhotos`.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "${1:?out dir}"
FFMPEG=/opt/homebrew/bin/ffmpeg
OPTS=(-hide_banner -loglevel error -y)
# photo NAME SIZE SEED TYPE: one frame of a synthetic gradient, as a JPEG.
photo() {
  "$FFMPEG" "${OPTS[@]}" -f lavfi -i "gradients=s=$2:seed=$3:type=$4:nb_colors=4" \
    -frames:v 1 -q:v 6 "$1.jpg"
}
photo harbour 1280x853 3 linear
photo cliff 720x1080 8 radial
photo meadow 900x900 13 circular
photo skyline 1600x600 21 linear
photo tower 500x1400 34 spiral
photo pebble 240x180 55 radial
photo dunes 1200x900 89 circular
photo lagoon 1080x1350 144 spiral
```
