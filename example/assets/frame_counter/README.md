# Frame counter

Nine clips for the demo's `FrameCounterPack`: a GIF, a WebP and an MP4 at
10, 15 and 25 fps, 192 x 144. Each frame shows its index as a big number and
in a binary bar under a band whose colour names the rate, so a screen
recording of a GIF scrolled off and back can be read frame by frame. The GIFs
and WebPs play through the engine's image codec, the MP4s through the video
decoder. Generated from a synthetic source: no third-party artwork.

The demo chat shows them after a "Frame counter" line among its showcase
messages (the newest ones by default); the panel's GIF page lists them first in a build with
`--dart-define=FRAME_COUNTER_GIFS=true`. `tool/frame_counter.dart` makes them
and reads recordings of them; its header has the frame's layout.

```shell
# From example/: needs ffmpeg (with libx264) and gif2webp on the PATH.
dart run tool/frame_counter.dart make
# Per clip on screen, each return: the frame it left on, the first frame
# back, the frames after, and any step but one or any frame held too long.
dart run tool/frame_counter.dart read recording.mp4
```
