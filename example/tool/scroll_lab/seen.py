"""What the eye saw in a replayed scroll: visible hitches per display refresh.

    python3 tool/scroll_lab/seen.py <trace.pftrace> <tape.json>

For every display refresh it finds the app frame on screen (the buffer the
compositor latched) and the content position in it (the lab's `LABy <px>`
slice). During steady motion (the neighbouring steps agree in sign and size)
a refresh whose step is outside 0.5-1.5x the neighbours' median is a visible
hitch, labelled by what was late. Refreshes within 60 ms of a tape event are
not judged: the finger is down, or just lifted.

The tape sets those windows: an app message is not a touch, and background
work sends many. Prints the denominator with every count, and exits non-zero
when no refresh was in steady motion, since 0 hitches of 0 is no result.

Needs `pip install perfetto`.
"""

import bisect
import collections
import json
import statistics
import sys

from perfetto.trace_processor import TraceProcessor

APP = "com.example.chat_scroll_view%"
VSYNC_NS = 1e9 / 120
POINTER_WINDOW_NS = 60e6

trace_path, tape_path = sys.argv[1], sys.argv[2]
tp = TraceProcessor(trace=trace_path)


def q(sql):
    return list(tp.query(sql))


upid = q(f"select upid from process where name like '{APP}' order by upid desc limit 1")[0].upid
main = q(f"select utid from thread where upid={upid} and tid=(select pid from process where upid={upid})")[0].utid
raster = q(f"select utid from thread where upid={upid} and name='1.raster'")[0].utid


def top_slices(utid, name):
    """(start, end) of the outermost `name` slices on a thread."""
    rows = q(
        f"select s.ts, s.dur from slice s join thread_track tt on s.track_id=tt.id "
        f"where tt.utid={utid} and s.name='{name}' and s.depth=(select min(depth) "
        f"from slice s2 join thread_track t2 on s2.track_id=t2.id "
        f"where t2.utid={utid} and s2.name='{name}') order by s.ts"
    )
    return [(r.ts, r.ts + r.dur) for r in rows]


ui = top_slices(main, "VsyncProcessCallback")
ui_starts = [a for a, _ in ui]
draws = top_slices(raster, "GPURasterizer::Draw")
queued = [a for a, _ in top_slices(raster, "queueBuffer")]
marks = [(r.ts, float(r.name[5:])) for r in q("select ts, name from slice where name like 'LABy %' order by ts")]
mark_ts = [t for t, _ in marks]

buffer_track = q(
    "select id from counter_track where name like "
    "'BufferTX - %SurfaceView[com.example.chat_scroll_view%' limit 1"
)[0].id
counter = [(r.ts, r.value) for r in q(f"select ts, value from counter where track_id={buffer_track} order by ts")]
# A buffer is latched when the count of queued buffers drops.
latches = [t for (t, v), (_, prev) in zip(counter[1:], counter[:-1]) if v < prev]


def y_at(t):
    i = bisect.bisect_right(mark_ts, t) - 1
    return marks[i][1] if i >= 0 else None


# Each presented app frame: when it was latched, its content position, and
# its UI, draw and queue-to-latch times in ms.
frames = []
li = 0
for d0, d1 in draws:
    k = bisect.bisect_left(queued, d0)
    if k >= len(queued) or queued[k] > d1 + 5e6:
        continue
    while li < len(latches) and latches[li] < queued[k]:
        li += 1
    if li >= len(latches):
        break
    j = bisect.bisect_right(ui_starts, d0) - 1
    frames.append(dict(
        latch=latches[li],
        y=y_at(ui[j][1]),
        ui=(ui[j][1] - ui[j][0]) / 1e6,
        draw=(d1 - d0) / 1e6,
        queue=(latches[li] - queued[k]) / 1e6,
    ))
    li += 1

refreshes = [r.ts for r in q(
    "select ts from actual_frame_timeline_slice where upid=(select upid from "
    "process where name='/system/bin/surfaceflinger') order by ts"
)]
frame_latches = [f["latch"] for f in frames]
shown = []
for t in refreshes:
    i = bisect.bisect_right(frame_latches, t) - 1
    shown.append((t, frames[i] if i >= 0 else None))

# The tape's event times, moved onto this trace by matching its first drag
# move to the first content move.
tape = json.load(open(tape_path))
t0, down_y = tape[0][0], tape[0][7]
first_drag = next((e[0] for e in tape if abs(e[7] - down_y) > 18), None)
first_move = next((b[0] for a, b in zip(marks, marks[1:]) if a[1] != b[1]), None)
if first_drag is None or first_move is None:
    sys.exit("no drag in the tape or no content move in the trace: nothing to align")
offset = first_move - (first_drag - t0) * 1000
pointer = sorted(offset + (e[0] - t0) * 1000 for e in tape)


def pointer_near(t):
    lo = bisect.bisect_left(pointer, t - POINTER_WINDOW_NS)
    return bisect.bisect_left(pointer, t + POINTER_WINDOW_NS) > lo


hitches = collections.Counter()
examples = collections.defaultdict(list)
steady = 0
for i in range(4, len(shown) - 4):
    seq = [shown[k][1] for k in range(i - 4, i + 5)]
    if any(s is None or s["y"] is None for s in seq):
        continue
    if shown[i + 4][0] - shown[i - 4][0] > 8.6 * VSYNC_NS:
        continue  # the display paused
    if pointer_near(shown[i][0]):
        continue
    steps = [seq[k]["y"] - seq[k - 1]["y"] for k in range(1, 9)]
    around = steps[:3] + steps[4:7]
    typical = statistics.median(around)
    if abs(typical) < 1.0 or any(x * typical < 0 for x in around):
        continue  # not in steady motion
    steady += 1
    ratio = steps[3] / typical
    if 0.5 <= ratio <= 1.5:
        continue
    cur, prev, nxt = seq[4], seq[3], seq[5]
    if cur is prev:
        late = (
            "next frame UI long" if nxt["ui"] > 6.5
            else "next frame raster long" if nxt["draw"] > 5
            else "next frame latched late" if nxt["queue"] > VSYNC_NS * 1.3 / 1e6
            else "next frame on time"
        )
        why = f"repeat: no new frame this refresh ({late})"
    elif ratio < 0.5:
        why = "new frame, content barely moved"
    else:
        why = "new frame, content jumped ahead"
    hitches[why] += 1
    examples[why].append((round(typical, 1), round(steps[3], 1), round(cur["ui"], 1), round(cur["draw"], 1), round(cur["queue"], 1)))

total = sum(hitches.values())
print(f"refreshes: {len(refreshes)}, in steady motion: {steady}, "
      f"visible hitches: {total} of {steady} ({100 * total / max(1, steady):.2f}%)")
for why, n in hitches.most_common():
    print(f"  {n:4d} {why}")
    print(f"       e.g. (typical px, this px, ui ms, draw ms, queue ms) {examples[why][:4]}")
if steady == 0:
    sys.exit("no refresh in steady motion: wrong tape, no LABy marks, or the trace missed the replay")
