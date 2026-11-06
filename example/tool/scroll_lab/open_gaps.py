"""The chat open in a trace: presented-frame gaps and long slices after the tap.

    python3 tool/scroll_lab/open_gaps.py <trace.pftrace>

Takes the first input dispatch as the tap and judges the 600 ms after it,
where the route transition runs. Run on a `scenario.sh open` trace. Exits
non-zero when no tap or no presented frame was found.

Needs `pip install perfetto`.
"""

import sys

from perfetto.trace_processor import TraceProcessor

APP = "com.example.chat_scroll_view%"
WINDOW_NS = 600e6

tp = TraceProcessor(trace=sys.argv[1])


def q(sql):
    return list(tp.query(sql))


app = q(f"select upid, pid from process where name like '{APP}' order by upid desc limit 1")[0]
main = q(f"select utid from thread where upid={app.upid} and tid={app.pid}")[0].utid
raster = q(f"select utid from thread where upid={app.upid} and name='1.raster'")[0].utid
tap = q(
    f"select min(s.ts) t from slice s join thread_track tt on s.track_id=tt.id "
    f"where tt.utid={main} and s.name like '%deliverInputEvent%'"
)[0].t
if tap is None:
    sys.exit("no input dispatch in the trace: the tap missed the app")

buffer_track = q(
    "select id from counter_track where name like "
    "'BufferTX - %SurfaceView[com.example.chat_scroll_view%' limit 1"
)[0].id
counter = [(r.ts, r.value) for r in q(
    f"select ts, value from counter where track_id={buffer_track} "
    f"and ts > {tap} and ts < {tap + 2 * WINDOW_NS} order by ts"
)]
latches = [t for (t, v), (_, prev) in zip(counter[1:], counter[:-1]) if v < prev]
shown = [t for t in latches if t < tap + WINDOW_NS]
if not shown:
    sys.exit("no frame presented after the tap")
gaps = [round((b - a) / 1e6) for a, b in zip(shown, shown[1:]) if b - a > 12e6]


def long_slices(utid, over_ns):
    rows = q(
        f"select s.ts, s.dur, s.name from slice s join thread_track tt on s.track_id=tt.id "
        f"where tt.utid={utid} and s.depth=0 and s.dur > {over_ns} "
        f"and s.ts > {tap} and s.ts < {tap + WINDOW_NS} order by s.ts"
    )
    return [(round((r.ts - tap) / 1e6), round(r.dur / 1e6, 1), r.name[:40]) for r in rows]


print(f"frames in {WINDOW_NS / 1e6:.0f} ms: {len(shown)}, gaps > 12 ms: {gaps}, sum {sum(gaps)} ms")
print("  UI > 8 ms (at ms, dur ms, slice)    ", long_slices(main, 8e6))
print("  raster > 8 ms (at ms, dur ms, slice)", long_slices(raster, 8e6))
