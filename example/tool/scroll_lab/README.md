# Scroll lab

Device scripts for judging scroll smoothness and the chat open by what reaches
the screen. The app side is `lib/src/common/scroll_lab.dart`: switches and
commands over `adb shell am broadcast -a lab.SET`, a frame log in logcat
(`LAB` lines), a content-position mark per frame, and the pointer tape. It is
compiled in only with `--dart-define=SCROLL_LAB=true`.

`tool/chat_perf.dart` is the other suite: scripted scenarios judged against a
committed baseline. The lab is for questions that scenario does not answer:
the user's own gestures, replayed, and a count of the hitches they would see.

| Script | Does |
|---|---|
| `watch.sh start\|stop <session>` | Records the user's gestures as a tape, with a trace and raw touches |
| `replay.sh <tape> <session> [jump-id]` | Replays a tape under a trace |
| `ab.sh <label> <tape> [dart-defines...]` | One A/B arm: a clean profile build, `RUNS` replays, battery temperature per run |
| `scenario.sh open\|jump <session> ...` | From a fresh process: a cold open by tap, or a jump to a message |
| `seen.py <trace> <tape.json>` | Visible hitches per refresh in steady motion, by cause |
| `open_gaps.py <trace>` | Frame gaps and long slices in the 600 ms after the tap |

Sessions land in `perf/lab/<session>/` (gitignored). `DEVICE` picks the adb
device; the only attached one by default. The Python scripts need
`pip install perfetto`.

A typical round:

```shell
flutter run --profile --dart-define=SCROLL_LAB=true \
  --dart-define=DISK_CACHE=false \
  --dart-define-from-file=../config/development.json
tool/scroll_lab/watch.sh start s1                # the user scrolls
tool/scroll_lab/watch.sh stop s1
tool/scroll_lab/ab.sh base s1                    # arm A
LAB_ON=snap tool/scroll_lab/ab.sh snap s1        # arm B; alternate A B A B
python3 tool/scroll_lab/seen.py perf/lab/base-1/trace.pftrace perf/lab/s1/tape.json
```

A lab build turns the disk caches off with `--dart-define=DISK_CACHE=false`
(`ab.sh` passes it): the baked glyph pages and the media store (the Lottie
frames, Giphy's stills and clips) are then kept in memory only, and the store
is not swept, so every run starts as cold as
the last and leaves no file behind. With them on, a run after the first meets
warm caches, and a Giphy file found on disk is a request never sent: a net
tape recorded then lacks it, and a replay of it never reaches the tape. A
build without the define keeps them on, as a shipped client does.

The on/off switches (`lab_set <key> --ez value true|false`, or `LAB_ON` in
`ab.sh` for the ones off by default):

| Key | Off by default | Switches |
|---|---|---|
| `resampling` | yes | pointer samples resampled to the frame time |
| `snap` | yes | rows snapped to physical pixels |
| `plain` | yes | message bodies as plain text |
| `textures` | no | playing Lottie and video assets on platform textures |
| `glass` | no | the glass capture of the chat; off, every glass paints flat |

`video_cap` takes a number (`--es value 4`). An arm with the glass off:

```shell
adb shell am broadcast -a lab.SET --es key glass --ez value false
```

Before trusting a number:

- The trace inflates frames with many timeline events. Confirm a slow frame
  from the `LAB slow` lines of a run, not from the trace's slice length.
- The default chat source holds the heavy bodies (up to 155k characters).
  A run on `CHAT_SOURCE=sizes` never meets them.
- The Dart CPU profiler needs the app started by `flutter run --profile`;
  `am start` gives no samples.
- A run more than 2 °C over its arm's first is hot; its numbers swing more
  than most changes.
