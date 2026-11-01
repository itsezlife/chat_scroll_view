/// The traced pass (spec 8, 9): structural counts from a timeline.
///
/// `deterministic` scenarios also run once in a launch built with
/// `chat_scroll_view.trace=phase`. The app marks each measured window on the
/// timeline; the host derives, offline from the captured timeline, how many
/// children were built and how many layout and fan-out passes ran inside each
/// window. Tracing perturbs a run, so only counts come from this pass, never
/// timing.
library;

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// The counted sections are the engine's own names, not copies of them.

import 'dart:developer' show Timeline;

import 'package:chat_scroll_view/src/util/trace_section.dart' show TraceSection;

import 'defines.dart';
import 'metrics.dart';
import 'report_document.dart';

/// Whether this launch is the traced one (`CHAT_PERF_TRACED=true`). A
/// compile-time constant: the timing launches never emit a window mark.
const bool kTracedLaunch = bool.fromEnvironment(ChatPerfDefine.traced);

const _startMark = 'chat_perf.window.start:';
const _endMark = 'chat_perf.window.end:';

/// The timeline event name that opens or closes window [name].
String traceWindowMark(String name, {required bool start}) =>
    '${start ? _startMark : _endMark}$name';

/// Marks the edge of a measured window on the timeline; a no-op outside the
/// traced launch.
void markTraceWindow(String name, {required bool start}) {
  if (!kTracedLaunch) return;
  Timeline.instantSync(traceWindowMark(name, start: start));
}

/// The driver report key of [scenarioId]'s timeline. It ends in `_timeline`,
/// which is how the host driver stores it as `<key>.timeline.json`.
String traceReportKey(String scenarioId) =>
    'chat_perf_trace_${scenarioId.replaceAll('.', '_')}_timeline';

/// The file the driver writes for [scenarioId]'s timeline in a run directory.
String traceTimelineFile(String scenarioId) =>
    '${traceReportKey(scenarioId)}.timeline.json';

/// The counted [TraceSection]s by their timeline label, to the metric each
/// count is.
final _counted = <String, String>{
  TraceSection.childBuild.label: 'trace.children_built',
  TraceSection.layoutMode.label: 'trace.layout_passes',
  TraceSection.layoutFanOut.label: 'trace.fan_out_passes',
};

/// Per window, the structural counts of a captured [timeline] (the
/// `Timeline.toJson` shape): `trace.children_built`, `trace.layout_passes`
/// (one `layout.mode` section opens every `performLayout`) and
/// `trace.fan_out_passes`. A window left open ends at the last event.
Map<String, Map<String, Metric>> traceCounts(Map<String, Object?> timeline) {
  final events = [
    for (final e in (timeline['traceEvents'] as List<Object?>?) ?? const [])
      if (e case {'name': final String name, 'ts': final num ts})
        (name: name, ts: ts, ph: e['ph'] as String?),
  ];
  final starts = <String, num>{};
  final ends = <String, num>{};
  num last = 0;
  for (final e in events) {
    if (e.ts > last) last = e.ts;
    if (e.name.startsWith(_startMark)) {
      starts[e.name.substring(_startMark.length)] = e.ts;
    } else if (e.name.startsWith(_endMark)) {
      ends[e.name.substring(_endMark.length)] = e.ts;
    }
  }
  return {
    for (final w in starts.entries)
      w.key: {
        for (final name in _counted.values)
          name: Metric(
            events
                .where(
                  (e) =>
                      (e.ph == 'B' || e.ph == 'X') &&
                      _counted[e.name] == name &&
                      e.ts >= w.value &&
                      e.ts <= (ends[w.key] ?? last),
                )
                .length
                .toDouble(),
            kind: MetricKind.count,
            role: MetricRole.headline,
            pass: MetricPass.traced,
          ),
      },
  };
}

/// The document of the traced pass: [counts] per `id@version`, trace metrics
/// only. A timing metric here is a bug: timing never comes from this pass.
MetricsDocument tracedDocument({
  required LaunchMeta meta,
  required Map<String, Map<String, Map<String, Metric>>> counts,
}) {
  for (final s in counts.values) {
    for (final w in s.values) {
      for (final MapEntry(key: name, value: metric) in w.entries) {
        if (metric.pass != MetricPass.traced) {
          throw ArgumentError.value(
            name,
            'counts',
            'only trace metrics may come from the traced pass',
          );
        }
      }
    }
  }
  return MetricsDocument(meta: meta, scenarios: counts);
}

/// [timing] with the counts of [traced] added to its windows. Timing metrics
/// of [traced] are not taken (there are none in a [tracedDocument]).
MetricsDocument withTracedCounts(
  MetricsDocument timing,
  MetricsDocument traced,
) {
  final scenarios = {
    for (final s in timing.scenarios.entries)
      s.key: {
        for (final w in s.value.entries) w.key: {...w.value},
      },
  };
  for (final s in traced.scenarios.entries) {
    for (final w in s.value.entries) {
      scenarios
          .putIfAbsent(s.key, () => {})
          .putIfAbsent(w.key, () => {})
          .addAll(w.value);
    }
  }
  return MetricsDocument(
    meta: timing.meta,
    scenarios: scenarios,
    skipped: timing.skipped,
  );
}

/// [rounds] with the counts of traced launch `i` added to round `i`.
///
/// Each traced launch joins one timing round, so a baseline made of the
/// rounds gets the counts' spread over the traced launches, and a run's median
/// is the median of them; rounds past the traced launches carry no counts.
/// More traced launches than rounds is a bug.
List<MetricsDocument> withTracedRounds(
  List<MetricsDocument> rounds,
  List<MetricsDocument> traced,
) {
  if (traced.length > rounds.length) {
    throw ArgumentError.value(
      traced.length,
      'traced',
      'more traced launches than the ${rounds.length} timing rounds',
    );
  }
  return [
    for (final (i, round) in rounds.indexed)
      i < traced.length ? withTracedCounts(round, traced[i]) : round,
  ];
}
