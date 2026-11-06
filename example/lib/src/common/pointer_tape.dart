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

import 'package:flutter/foundation.dart' show visibleForTesting;

/// A system event the tape carries beside the pointer rows: input that
/// reaches the app without a pointer packet.
enum TapeSystemEvent {
  /// Android Back delivered as `popRoute` (no pre-IME claim was active).
  back('back'),

  /// Android Back claimed before the IME by the host's pre-IME back claim
  /// (`ChatPreImeBackBinding.handleNativeBack`); `popRoute` never fires.
  backPreIme('back-pre-ime'),

  /// The soft keyboard went away with no pointer or Back of the app's own
  /// in the moment before: the system consumed Back to hide it.
  imeHidden('ime-hidden'),

  /// The soft keyboard appeared. Diagnostic only, never replayed: tapping the
  /// field in the replay shows it.
  imeShown('ime-shown');

  const TapeSystemEvent(this.wire);

  /// The `e` value in the file.
  final String wire;

  /// Whether a replay dispatches it.
  bool get replayed => this != imeShown;

  /// The event named [wire] in the file.
  static TapeSystemEvent fromWire(String wire) =>
      values.firstWhere((e) => e.wire == wire);
}

/// One tape row on the shared timeline (engine monotonic microseconds).
sealed class TapeRow {
  const TapeRow();

  /// When the row happened.
  int get time;
}

/// A pointer sample: [values] is the 21-number row of [PointerTape].
final class PointerRow extends TapeRow {
  /// Wraps [values].
  const PointerRow(this.values);

  /// The encoded sample, `values[0]` being its timestamp.
  final List<num> values;

  @override
  int get time => values[0].toInt();
}

/// A [TapeSystemEvent] at [time].
final class SystemRow extends TapeRow {
  /// Creates the row.
  const SystemRow(this.time, this.event);

  @override
  final int time;

  /// What happened.
  final TapeSystemEvent event;
}

/// The tape file: one JSON array in timeline order.
///
/// A pointer row is an array of 21 numbers (see [PointerTape]); this is the
/// whole of the original format, so a tape recorded before system events
/// existed still decodes. A system row is an object
/// `{"t": <micros>, "e": "<wire name>"}` (see [TapeSystemEvent]) and shares
/// the pointer rows' clock. Rows are told apart by JSON type alone.
abstract final class TapeCodec {
  /// Serializes [rows], ordered by time (stable, so rows of one instant keep
  /// their order).
  static String encode(List<TapeRow> rows) {
    final sorted = [...rows]..sort((a, b) => a.time.compareTo(b.time));
    return jsonEncode([
      for (final row in sorted)
        switch (row) {
          PointerRow(:final values) => values,
          SystemRow(:final time, :final event) => {'t': time, 'e': event.wire},
        },
    ]);
  }

  /// Parses a tape file's text.
  static List<TapeRow> decode(String text) => [
    for (final row in jsonDecode(text) as List<Object?>)
      switch (row) {
        final List<Object?> values => PointerRow([...values.cast<num>()]),
        final Map<String, Object?> map => SystemRow(
          (map['t']! as num).toInt(),
          TapeSystemEvent.fromWire(map['e']! as String),
        ),
        _ => throw FormatException('Unknown tape row', row),
      },
  ];
}

/// Records the pointer packets the engine hands to the framework, and the
/// system events they do not carry, and plays them back with their original
/// spacing.
///
/// Sits in front of the binding's `onPointerDataPacket`, so a replay goes
/// through the same hit testing, gesture arena and (when on) resampling as a
/// finger. Timestamps are rebased onto the engine's monotonic clock at
/// replay, so velocity tracking sees the recorded intervals. System events are
/// stamped with [Timeline.now], the same clock, and replay in timeline order
/// between the pointer rows (see [TapeCodec]).
abstract final class PointerTape {
  static void Function(PointerDataPacket)? _forward;
  static List<TapeRow>? _recording;
  static bool _replaying = false;
  static int _lastInputAt = 0;

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
          tape.add(PointerRow(_encode(d)));
        }
        _lastInputAt = Timeline.now;
      }
      forward(packet);
    };
  }

  /// Whether a recording is running.
  static bool get recording => _recording != null;

  /// Microseconds since the last pointer sample or Back the recording saw.
  static int get sinceInputMicros => Timeline.now - _lastInputAt;

  /// Starts a new recording, dropping one in progress.
  static void start() => _recording = [];

  /// Adds [event] at [at] (default now) to the recording. A no-op when not
  /// recording or while a replay runs, so a replayed event is not re-recorded.
  static void note(TapeSystemEvent event, {int? at}) {
    if (_replaying) return;
    final tape = _recording;
    if (tape == null) return;
    final time = at ?? Timeline.now;
    tape.add(SystemRow(time, event));
    if (event == TapeSystemEvent.back || event == TapeSystemEvent.backPreIme) {
      _lastInputAt = time;
    }
  }

  /// Stops the recording and writes it to `<dir>/<name>.json`. Returns the
  /// row count.
  static Future<int> stop(String dir, String name) async {
    final tape = _recording;
    _recording = null;
    if (tape == null) return 0;
    await File('$dir/$name.json').writeAsString(TapeCodec.encode(tape));
    return tape.length;
  }

  /// Plays `<dir>/<name>.json` back through the binding, dispatching system
  /// events with [system]. Completes after the last row.
  static Future<int> replay(
    String dir,
    String name, {
    required Future<void> Function(TapeSystemEvent event) system,
  }) async {
    final forward = _forward;
    if (forward == null || _replaying) return 0;
    final rows = TapeCodec.decode(await File('$dir/$name.json').readAsString());
    _replaying = true;
    try {
      return await play(rows, forward: forward, system: system);
    } finally {
      _replaying = false;
    }
  }

  /// The replay loop: waits for each row's time, sends pointer rows due
  /// together as one packet and every other row on its own, in order.
  @visibleForTesting
  static Future<int> play(
    List<TapeRow> rows, {
    required void Function(PointerDataPacket) forward,
    required Future<void> Function(TapeSystemEvent event) system,
  }) async {
    if (rows.isEmpty) return 0;
    final t0 = rows.first.time;
    final base = Timeline.now;
    final clock = Stopwatch()..start();
    var i = 0;
    while (i < rows.length) {
      final due = rows[i].time - t0;
      final wait = due - clock.elapsedMicroseconds;
      if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait));
      if (rows[i] case SystemRow(:final event)) {
        i++;
        if (event.replayed) await system(event);
        continue;
      }
      // Everything due by now goes out in one packet, as the engine
      // batches samples that arrive between two deliveries.
      final batch = <PointerData>[];
      final now = clock.elapsedMicroseconds;
      while (i < rows.length &&
          rows[i] is PointerRow &&
          rows[i].time - t0 <= now) {
        batch.add(_decode((rows[i] as PointerRow).values, base - t0));
        i++;
      }
      forward(PointerDataPacket(data: batch));
    }
    return rows.length;
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
