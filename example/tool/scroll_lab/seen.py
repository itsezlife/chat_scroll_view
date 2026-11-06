"""What the eye saw in a replayed scroll: visible hitches per display refresh.

    python3 tool/scroll_lab/seen.py <trace.pftrace> <tape.json> [--mark LABp]

For every display refresh it finds the app frame on screen (the buffer the
compositor latched) and the content position in it (the lab's `LABy <px>`
slice for the chat, `--mark LABp` for the panel page's catalogue). During steady motion (the neighbouring steps agree in sign and size)
a refresh whose step is outside 0.5-1.5x the neighbours' median is a visible
hitch, labelled by what was late. Refreshes within 60 ms of a tape event are
not judged: the finger is down, or just lifted. A hitch is one or more
judged refreshes in a row (a repeat and the catch-up after it are one hitch);
the rate is hitches per second of steady motion (judged refreshes / 120).

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

args = sys.argv[1:]
mark = "LABy"
if "--mark" in args:
    i = args.index("--mark")
    mark = args[i + 1]
    del args[i:i + 2]
trace_path, tape_path = args[0], args[1]
tp = TraceProcessor(trace=trace_path)


def q(sql):
    return list(tp.query(sql))


upid = q(f"select upid from process where name like '{APP}' order by upid desc limit 1")[0].upid
main = q(f"select utid from thread where upid={upid} and tid=(select pid from process where upid={upid})")[0].utid
raster = q(f"select utid from thread where upid={upid} and name='1.raster'")[0].utid


def top_slices(utid, name, outermost=True):
    """(start, end) of the `name` slices on a thread, the outermost only
    unless told otherwise (a slice that never nests may sit at any depth)."""
    depth = (
        f"and s.depth=(select min(depth) from slice s2 join thread_track t2 "
        f"on s2.track_id=t2.id where t2.utid={utid} and s2.name='{name}')"
        if outermost else ""
    )
    rows = q(
        f"select s.ts, s.dur from slice s join thread_track tt on s.track_id=tt.id "
        f"where tt.utid={utid} and s.name='{name}' {depth} order by s.ts"
    )
    return [(r.ts, r.ts + r.dur) for r in rows]


ui = top_slices(main, "VsyncProcessCallback")
ui_starts = [a for a, _ in ui]
renders = [a for a, _ in top_slices(main, "Animator::Render", outermost=False)]
draws = top_slices(raster, "GPURasterizer::Draw")
snapshots = top_slices(raster, "SnapshotDisplayList (impeller)")
queued = [a for a, _ in top_slices(raster, "queueBuffer")]
marks = [(r.ts, float(r.name[len(mark) + 1:])) for r in q(f"select ts, name from slice where name like '{mark} %' order by ts")]
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


def busy(spans, a, b):
    """ms of [a, b] covered by spans (sorted, disjoint)."""
    i = max(0, bisect.bisect_left(spans, (a, a)) - 1)
    total = 0
    while i < len(spans) and spans[i][0] < b:
        total += max(0, min(b, spans[i][1]) - max(a, spans[i][0]))
        i += 1
    return total / 1e6


# Each presented app frame: when it was latched, its content position, and
# its timings in ms: UI (vsync callback), raster wait (layer tree handed over
# to draw start) and how much of that wait went to snapshots, draw, and queue
# to latch. A layer tree is drawn in the order it was rendered, so the k-th
# draw takes the oldest UI frame not drawn yet.
frames = []
li = 0
ri = 0
for d0, d1 in draws:
    while ri + 1 < len(renders) and renders[ri + 1] < d0 and renders[ri] < d0 - 100e6:
        ri += 1  # a tree never drawn (resynchronise)
    if ri >= len(renders) or renders[ri] > d0:
        continue
    r = renders[ri]
    ri += 1
    k = bisect.bisect_left(queued, d0)
    if k >= len(queued) or queued[k] > d1 + 5e6:
        continue
    while li < len(latches) and latches[li] < queued[k]:
        li += 1
    if li >= len(latches):
        break
    j = bisect.bisect_right(ui_starts, r) - 1
    frames.append(dict(
        latch=latches[li],
        vsync=ui[j][0],
        y=y_at(r),
        ui=(ui[j][1] - ui[j][0]) / 1e6,
        wait=(d0 - r) / 1e6,
        snap=busy(snapshots, r, d0),
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

# The tape's event times on this trace: from the replay's `LABtape0` slice
# (the tape's time zero), else by matching the tape's first drag move (18 px
# from its own down) to the first content move.
tape = [e for e in json.load(open(tape_path)) if len(e) > 7]
t0 = tape[0][0]
zero = q("select ts from slice where name='LABtape0' order by ts desc limit 1")
if zero:
    offset = zero[0].ts - t0 * 1000
else:
    downs, first_drag = {}, None
    for e in tape:
        if e[1] == 4:
            downs[e[5]] = e[7]
        elif e[5] in downs and abs(e[7] - downs[e[5]]) > 18:
            first_drag = e[0]
            break
    first_move = next((b[0] for a, b in zip(marks, marks[1:]) if a[1] != b[1]), None)
    if first_drag is None or first_move is None:
        sys.exit("no drag in the tape or no content move in the trace: nothing to align")
    offset = first_move - first_drag * 1000
pointer = sorted(offset + e[0] * 1000 for e in tape)


def pointer_near(t):
    lo = bisect.bisect_left(pointer, t - POINTER_WINDOW_NS)
    return bisect.bisect_left(pointer, t + POINTER_WINDOW_NS) > lo


y_low = min(y for _, y in marks) if marks else 0
y_high = max(y for _, y in marks) if marks else 0


def at_edge(f):
    """The content rests at its start or end: a fling stops there by design."""
    return f["y"] <= y_low + 0.5 or f["y"] >= y_high - 0.5


main_top = q(
    f"select s.ts, s.dur, s.name from slice s join thread_track tt on s.track_id=tt.id "
    f"where tt.utid={main} and s.depth=0 order by s.ts"
)
main_top_ts = [r.ts for r in main_top]


def busiest_between(a, b):
    """Name and ms of the longest main-thread slice overlapping [a, b]."""
    i = max(0, bisect.bisect_left(main_top_ts, a) - 1)
    best = ("idle", 0)
    while i < len(main_top) and main_top[i].ts < b:
        r = main_top[i]
        d = (min(b, r.ts + r.dur) - max(a, r.ts)) / 1e6
        if d > best[1] and r.name != "VsyncProcessCallback":
            best = (r.name, d)
        i += 1
    return best


def frame_cause(prev, cur):
    """Why `cur` (the frame after `prev`) reached the screen late or stale."""
    if cur["vsync"] - prev["vsync"] > 1.5 * VSYNC_NS:
        name, ms = busiest_between(prev["vsync"] + VSYNC_NS, cur["vsync"])
        return f"UI started a vsync late (main thread: {name})"
    return (
        "UI long" if cur["ui"] > 6.5
        else "raster behind, snapshots" if cur["wait"] > 3 and cur["snap"] > cur["wait"] / 2
        else "raster behind" if cur["wait"] > 3
        else "raster long" if cur["draw"] > 5
        else "latched late" if cur["queue"] > VSYNC_NS * 1.3 / 1e6
        else "on time"
    )


def clusters(flagged):
    """Flagged refreshes at most one apart are one hitch, named by its first."""
    events, last = collections.Counter(), None
    for i, why in flagged:
        if last is None or i - last > 2:
            events[why] += 1
        last = i
    return events


# 1. Gliding (no finger near): the content step at each refresh against its
# neighbours' median.
hitches = collections.Counter()
examples = collections.defaultdict(list)
steady = 0
glide_flags = []
for i in range(4, len(shown) - 4):
    seq = [shown[k][1] for k in range(i - 4, i + 5)]
    if any(s is None or s["y"] is None for s in seq):
        continue
    if shown[i + 4][0] - shown[i - 4][0] > 8.6 * VSYNC_NS:
        continue  # the display paused
    if pointer_near(shown[i][0]) or at_edge(seq[4]):
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
        why = f"repeat: no new frame this refresh ({frame_cause(prev, nxt)})"
        late = nxt
    else:
        # A frame that started a vsync late shows as a jump on the screen once
        # the queued buffers hide the gap: look at it and at the one before.
        late = cur if cur["vsync"] - prev["vsync"] >= prev["vsync"] - seq[2]["vsync"] else prev
        before = prev if late is cur else seq[2]
        moved = "barely moved" if ratio < 0.5 else "jumped ahead"
        why = f"new frame, content {moved} ({frame_cause(before, late)})"
    hitches[why] += 1
    glide_flags.append((i, why))
    examples[why].append((round(typical, 1), round(steps[3], 1), round(late["ui"], 1), round(late["wait"], 1), round(late["snap"], 1), round(late["draw"], 1), round(late["queue"], 1)))

# 2. Under the finger: replayed input is not on the display clock, so steps
# are uneven by construction; judge the frame cadence instead. A refresh in
# motion is a hitch when it repeats the previous frame, or shows a frame
# whose UI started more than 1.5 vsyncs after the one before although input
# had arrived in between.
pointer_ts = pointer
drag_motion = 0
drag_flags = []
for i in range(2, len(shown) - 2):
    t, cur = shown[i]
    prev = shown[i - 1][1]
    if cur is None or prev is None or cur["y"] is None or not pointer_near(t):
        continue
    ys = [shown[k][1]["y"] for k in (i - 2, i + 2) if shown[k][1] and shown[k][1]["y"] is not None]
    if len(ys) < 2 or abs(ys[1] - ys[0]) < 1.0 or t - shown[i - 1][0] > 1.5 * VSYNC_NS:
        continue  # not moving, or the display paused
    drag_motion += 1
    if cur is prev:
        nxt = shown[i + 1][1]
        if nxt is not None and nxt is not cur:
            drag_flags.append((i, f"repeat ({frame_cause(cur, nxt)})"))
    elif cur["vsync"] - prev["vsync"] > 1.5 * VSYNC_NS:
        a = bisect.bisect_right(pointer_ts, prev["vsync"])
        if a < len(pointer_ts) and pointer_ts[a] < cur["vsync"] - VSYNC_NS:
            drag_flags.append((i, frame_cause(prev, cur)))

total = sum(hitches.values())
glide = clusters(glide_flags)
drag = clusters(drag_flags)
seconds = steady / 120
drag_seconds = drag_motion / 120
n, m = sum(glide.values()), sum(drag.values())
print(f"refreshes: {len(refreshes)}; gliding in steady motion: {steady} ({seconds:.1f} s), "
      f"refreshes off: {total} of {steady} ({100 * total / max(1, steady):.2f}%), "
      f"hitches: {n} = {n / max(seconds, 1e-9):.2f}/s; "
      f"under the finger in motion: {drag_motion} ({drag_seconds:.1f} s), "
      f"cadence hitches: {m} = {m / max(drag_seconds, 1e-9):.2f}/s; "
      f"all: {(n + m) / max(seconds + drag_seconds, 1e-9):.2f}/s of motion")
for why, k in glide.most_common():
    print(f"  glide {k:4d} {why}")
for why, k in drag.most_common():
    print(f"  drag  {k:4d} {why}")
for why, k in hitches.most_common():
    print(f"  {k:4d} {why}")
    print(f"       e.g. (typical px, this px; late frame's ui, raster wait, of it snapshots, draw, queue ms) {examples[why][:4]}")
if steady == 0:
    sys.exit("no refresh in steady motion: wrong tape, no position marks, or the trace missed the replay")
