import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui'
    show
        PlatformDispatcher,
        PointerChange,
        PointerData,
        PointerDataPacket,
        PointerDeviceKind,
        PointerSignalKind;

/// Records the pointer packets the engine hands to the framework, and plays
/// them back with their original spacing.
///
/// Sits in front of the binding's `onPointerDataPacket`, so a replay goes
/// through the same hit testing, gesture arena and (when on) resampling as a
/// finger. Timestamps are rebased onto the engine's monotonic clock at
/// replay, so velocity tracking sees the recorded intervals.
abstract final class PointerTape {
  static void Function(PointerDataPacket)? _forward;
  static List<List<num>>? _recording;
  static bool _replaying = false;

  /// Wraps the binding's pointer entry point. Call after the binding exists.
  static void install() {
    if (_forward != null) return;
    final dispatcher = PlatformDispatcher.instance;
    final forward = dispatcher.onPointerDataPacket;
    if (forward == null) return;
    _forward = forward;
    dispatcher.onPointerDataPacket = (packet) {
      if (_recording case final tape? when !_replaying) {
        for (final d in packet.data) {
          tape.add(_encode(d));
        }
      }
      forward(packet);
    };
  }

  /// Whether a recording is running.
  static bool get recording => _recording != null;

  /// Starts a new recording, dropping one in progress.
  static void start() => _recording = [];

  /// Stops the recording and writes it to `<dir>/<name>.json`. Returns the
  /// event count.
  static Future<int> stop(String dir, String name) async {
    final tape = _recording;
    _recording = null;
    if (tape == null) return 0;
    await File('$dir/$name.json').writeAsString(jsonEncode(tape));
    return tape.length;
  }

  /// Plays `<dir>/<name>.json` back. Completes after the last event.
  static Future<int> replay(String dir, String name) async {
    final forward = _forward;
    if (forward == null || _replaying) return 0;
    final raw = jsonDecode(await File('$dir/$name.json').readAsString());
    final events = [
      for (final e in raw as List<Object?>)
        [...(e as List<Object?>).cast<num>()],
    ];
    if (events.isEmpty) return 0;
    _replaying = true;
    try {
      final t0 = events.first[0].toInt();
      final base = Timeline.now;
      final clock = Stopwatch()..start();
      var i = 0;
      while (i < events.length) {
        final due = events[i][0].toInt() - t0;
        final wait = due - clock.elapsedMicroseconds;
        if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait));
        // Everything due by now goes out in one packet, as the engine
        // batches samples that arrive between two deliveries.
        final batch = <PointerData>[];
        final now = clock.elapsedMicroseconds;
        while (i < events.length && events[i][0].toInt() - t0 <= now) {
          batch.add(_decode(events[i], base - t0));
          i++;
        }
        forward(PointerDataPacket(data: batch));
      }
    } finally {
      _replaying = false;
    }
    return events.length;
  }

  static List<num> _encode(PointerData d) => [
    d.timeStamp.inMicroseconds,
    d.change.index,
    d.kind.index,
    d.signalKind?.index ?? 0,
    d.device,
    d.pointerIdentifier,
    d.physicalX,
    d.physicalY,
    d.physicalDeltaX,
    d.physicalDeltaY,
    d.buttons,
    d.pressure,
    d.pressureMax,
    d.size,
    d.radiusMajor,
    d.radiusMinor,
    d.scrollDeltaX,
    d.scrollDeltaY,
    d.embedderId,
    d.viewId,
    if (d.synthesized) 1 else 0,
  ];

  static PointerData _decode(List<num> e, int shiftMicros) => PointerData(
    timeStamp: Duration(microseconds: e[0].toInt() + shiftMicros),
    change: PointerChange.values[e[1].toInt()],
    kind: PointerDeviceKind.values[e[2].toInt()],
    signalKind: PointerSignalKind.values[e[3].toInt()],
    device: e[4].toInt(),
    pointerIdentifier: e[5].toInt(),
    physicalX: e[6].toDouble(),
    physicalY: e[7].toDouble(),
    physicalDeltaX: e[8].toDouble(),
    physicalDeltaY: e[9].toDouble(),
    buttons: e[10].toInt(),
    pressure: e[11].toDouble(),
    pressureMax: e[12].toDouble(),
    size: e[13].toDouble(),
    radiusMajor: e[14].toDouble(),
    radiusMinor: e[15].toDouble(),
    scrollDeltaX: e[16].toDouble(),
    scrollDeltaY: e[17].toDouble(),
    embedderId: e[18].toInt(),
    viewId: e[19].toInt(),
    synthesized: e[20] == 1,
  );
}
