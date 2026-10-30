# ADR 040: Engine trace seam

The engine can emit named timeline sections for attribution. They are compiled
in only by a build-time define, carry no public API and cost nothing in the
default build.

**Status**: Accepted  
**Date**: 2026-10-30  
**Relates to**: [ADR 030](030-testing-policy.md)

## Context

Frame times say a scenario is slow, not why. Attributing the time to a layout
step, a tick, the fetch poll or paint needs named spans in the timeline, and
counts (children built, fan-out passes) need a traced run. The shipping build
must stay the thing that is measured.

## Decision

- **Const gate.** `--dart-define=chat_scroll_view.trace=` takes `off` (the
  default and the value of anything unrecognised), `phase` or `fine`. The level
  is a compile-time constant, so in the default build `Trace.begin` and
  `Trace.end` are empty bodies.
- **Two levels.** `phase` covers each `performLayout` step of the
  [layout pipeline](../architecture/04-layout-pipeline.md), the Tier-1 tick, the
  fling and animator ticks, the fetch poll and paint (messages, scrollbar,
  highlight, selection). `fine` adds per-child build, layout and paint spans.
- **One vocabulary.** The `@internal` `TraceSection` enum
  (`lib/src/util/trace_section.dart`) holds every name, glossary-aligned, under
  one namespace: `chat_scroll_view.<section>`.
- **Begin / end pair, enum arguments only.** Call sites pass an enum constant:
  no closure, no map, no string built outside the gate. A closure-taking wrapper
  would allocate even when disabled.
- **Internal only, no public stats API.** Nothing is exported; the sections are
  read from a captured timeline.
- **Counts via a traced pass.** Count metrics come from the timeline of a run
  built with `phase`. Tracing perturbs a run, so timing never comes from the
  traced pass.

## Rejected alternatives

| Alternative | Why not |
| --- | --- |
| In-process counters and a public stats API | Adds public surface and per-frame cost in the shipping build, and every consumer pays for it |
| Measuring from outside only (frame timings) | Says a scenario is slow, not which step |
| `Timeline.timeSync(name, () {...})` wrappers | The closure allocates even when tracing is off |
| A runtime flag | The check and the call sites stay in the shipping build |

## Consequences

- An exception thrown between a `begin` and its `end` leaves that section open
  in a traced build only; the default build is unaffected.
- The text selection of markdown bodies paints inside the markdown engine, so
  `paint.selection` covers the viewport-owned emoji body highlight only.
- Capturing in a test needs the VM service: `flutter test --enable-vmservice
  --dart-define=chat_scroll_view.trace=phase test/widgets/trace_seam_test.dart`.
