# Video stickers

Ten files for the demo's video pack (`VideoStickerPack`): three WebM
stickers, four MP4 clips and three GIFs. The clips and GIFs have four
proportions, so the GIF page's justified rows have a mix to lay out. All are generated from synthetic
FFmpeg sources, so there is no third-party artwork here, and each
is well under 200 KB.

| File | What | Format |
| --- | --- | --- |
| `orbit.webm`, `pulse.webm`, `slide.webm` | A moving shape on transparent | VP9 with alpha (`yuva420p`), 512 x 512, 20 fps, 2 s |
| `gradient.mp4`, `spiral.mp4` | A drifting gradient, a turning spiral | H.264 `yuv420p`, 256 x 256, 24 fps, 2 s, no audio |
| `wave.mp4` | A radial gradient | H.264 `yuv420p`, 320 x 180 (16:9), 24 fps, 2 s, no audio |
| `tunnel.mp4` | A circular gradient | H.264 `yuv420p`, 180 x 240 (3:4), 24 fps, 2 s, no audio |
| `bars.gif`, `plasma.gif` | A test pattern, a colour plasma | GIF, 128 x 128, 10 fps, 2 s, 32 colours |
| `ticker.gif` | A gradient | GIF, 192 x 96 (2:1), 10 fps, 2 s, 32 colours |

## Regenerating

Needs the FFmpeg at `/opt/homebrew/bin/ffmpeg` with `libvpx-vp9` and
`libx264` (Homebrew's build has both). Save the script below as `gen.sh` and
run `bash gen.sh <this directory>`.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "${1:?out dir}"
FFMPEG=/opt/homebrew/bin/ffmpeg
OPTS=(-hide_banner -loglevel error -y)
SRC='color=c=black@0.0:s=512x512:r=20:d=2,format=yuva420p'
VP9=(-c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0 -b:v 0 -crf 38 -deadline good -cpu-used 4 -an)

# webm NAME INSIDE Y U V: a stencil INSIDE (non-zero where the shape is) coloured by a YUV triple
webm() {
  local name=$1 inside=$2 y=$3 u=$4 v=$5
  "$FFMPEG" "${OPTS[@]}" -f lavfi -i "$SRC" \
    -vf "geq=lum='if($inside,$y,16)':cb='if($inside,$u,128)':cr='if($inside,$v,128)':a='if($inside,255,0)'" \
    "${VP9[@]}" "$name.webm"
}
webm orbit 'lt(hypot(X-256-150*cos(2*PI*T),Y-256-150*sin(2*PI*T)),70)' 210 60 150
webm pulse 'between(hypot(X-256,Y-256),100+60*sin(2*PI*T),160+60*sin(2*PI*T))' 170 180 90
webm slide 'lt(max(abs(X-256-140*sin(2*PI*T)),abs(Y-256+60*cos(4*PI*T))),80)' 120 110 200

# Four H.264 clips (silent, yuv420p). The first two are square 256.
mp4() {
  local name=$1 src=$2
  "$FFMPEG" "${OPTS[@]}" -f lavfi -i "$src" -c:v libx264 -preset slow -crf 30 \
    -pix_fmt yuv420p -movflags +faststart -an "$name.mp4"
}
mp4 gradient 'gradients=s=256x256:r=24:d=2:speed=0.04:seed=7'
mp4 spiral 'gradients=s=256x256:r=24:d=2:speed=0.06:seed=11:type=spiral'
# Two more with their own proportions (the GIF page justifies rows by them).
mp4 wave 'gradients=s=320x180:r=24:d=2:speed=0.05:seed=21:type=radial'
mp4 tunnel 'gradients=s=180x240:r=24:d=2:speed=0.07:seed=5:type=circular'

# Tiny GIFs (10 fps, a 32 colour palette).
gif() {
  local name=$1 src=$2
  "$FFMPEG" "${OPTS[@]}" -f lavfi -i "$src" \
    -vf 'split[a][b];[a]palettegen=max_colors=32[p];[b][p]paletteuse' -loop 0 "$name.gif"
}
gif bars 'testsrc2=s=128x128:r=10:d=2'
gif plasma 'gradients=s=128x128:r=10:d=2:speed=0.08:seed=3:nb_colors=4'
gif ticker 'gradients=s=192x96:r=10:d=2:speed=0.09:seed=9:nb_colors=5'
```

A WebM keeps its alpha as a side channel, so `ffprobe` reports `yuv420p` for
it and the tag `alpha_mode=1` is what to look for. The native video library
reads that tag (`VideoInfo.hasAlpha`).
