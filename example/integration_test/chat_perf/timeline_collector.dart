/// Collects the engine's trace sections and the window marks of a traced
/// scenario from the VM timeline while it runs.
///
/// The VM keeps the newest ~32k timeline events and drops the oldest, which a
/// long scenario overflows before it ends: a capture taken afterwards has lost
/// the first window marks. The collector polls the timeline while the scenario
/// runs and keeps only the events the counts read.
///
/// The alternative to try is `flutter drive --endless-trace-buffer`, which
/// makes the VM keep every event so one capture at the end would do. It is
/// untested on the device (an endless buffer grows with the launch, and the
/// traced launch runs every scripted scenario), so the poller stays until a
/// device run shows the flag keeps the first window marks.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

/// Events the counts read: the engine's sections and the window marks.
bool _wanted(String name) =>
    name.startsWith('chat_scroll_view.') || name.startsWith('chat_perf.');

final class TimelineCollector {
  TimelineCollector._(this._service);

  final vm.VmService _service;
  final _events = <Map<String, Object?>>[];
  final _seen = <String>{};
  Timer? _timer;
  var _origin = 0;
  var _busy = false;

  /// Connects to this app's VM service and starts polling every [every].
  static Future<TimelineCollector> start({
    Duration every = const Duration(milliseconds: 400),
  }) async {
    final info = await developer.Service.controlWebServer(enable: true);
    final uri = info.serverWebSocketUri;
    if (uri == null) throw StateError('the VM service is unavailable');
    final service = await vm_io.vmServiceConnectUri(uri.toString());
    await service.setVMTimelineFlags(<String>['Dart']);
    await service.clearVMTimeline();
    final collector = TimelineCollector._(service);
    collector._timer = Timer.periodic(every, (_) => collector._poll());
    return collector;
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final timeline = await _service.getVMTimeline(timeOriginMicros: _origin);
      var newest = _origin;
      for (final event in timeline.traceEvents ?? const <vm.TimelineEvent>[]) {
        final json = event.json;
        if (json == null) continue;
        final ts = json['ts'];
        if (ts case final num t when t > newest) newest = t.toInt();
        if (json['name'] case final String name when _wanted(name)) {
          if (_seen.add('$ts|$name|${json['ph']}|${json['tid']}')) {
            _events.add({
              'name': name,
              'ph': json['ph'],
              'ts': ts,
              'tid': json['tid'],
            });
          }
        }
      }
      // Overlap a little: another thread's event may land after a later one.
      _origin = newest > 300000 ? newest - 300000 : newest;
    } finally {
      _busy = false;
    }
  }

  /// Stops polling, takes a last chunk and returns the kept events in the
  /// `Timeline.toJson` shape.
  Future<Map<String, Object?>> finish() async {
    _timer?.cancel();
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _poll();
    await _service.dispose();
    return {'traceEvents': _events};
  }
}
