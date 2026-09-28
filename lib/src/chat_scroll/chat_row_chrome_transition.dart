import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/src/chat_widgets/chat_message_change_params.dart';
import 'package:chat_scroll_view/src/util/sine_in_out_curve.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Exit fade of a transitioning row chrome item. Shorter than the extent
/// collapse ([kChatMessageChangeDuration]), which runs alongside it.
@internal
const Duration kChatRowChromeExitFadeDuration = Duration(milliseconds: 120);

/// Enter fade and scale of a transitioning row chrome item. Runs alongside
/// the extent growth.
@internal
const Duration kChatRowChromeEnterDuration = Duration(milliseconds: 250);

/// Scale a transitioning row chrome item enters from.
@internal
const double kChatRowChromeEnterScale = 0.9;

const _fadeCurve = SineInOutCurve();

/// One frame of a row chrome item transition: how much of the item's height
/// its slot keeps ([extent]), how visible it is ([opacity]), and how large it
/// paints ([scale]). All three lie in `[0, 1]`.
@internal
@immutable
final class ChatRowChromeTransitionFrame {
  /// A frame with the given factors.
  const ChatRowChromeTransitionFrame({
    required this.extent,
    required this.opacity,
    required this.scale,
  });

  /// The item at rest: full slot, opaque, unscaled.
  static const settled = ChatRowChromeTransitionFrame(
    extent: 1,
    opacity: 1,
    scale: 1,
  );

  /// Where an enter starts: no slot, transparent, at
  /// [kChatRowChromeEnterScale].
  static const hidden = ChatRowChromeTransitionFrame(
    extent: 0,
    opacity: 0,
    scale: kChatRowChromeEnterScale,
  );

  /// Fraction of the item's laid-out height its slot keeps. The rows around
  /// it move with the slot, not with the item.
  final double extent;

  /// Multiplies the opacity the item's delegate resolves.
  final double opacity;

  /// Paint scale about the item's center.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is ChatRowChromeTransitionFrame &&
      other.extent == extent &&
      other.opacity == opacity &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(extent, opacity, scale);

  @override
  String toString() =>
      'ChatRowChromeTransitionFrame(extent: $extent, opacity: $opacity, '
      'scale: $scale)';
}

/// One running leg: toward settled (entering) or gone (exiting), starting
/// from [from] at [start] on the clock's ticker.
final class _Leg {
  _Leg({required this.entering, required this.from, required this.start})
    : frame = from;

  /// Toward settled when `true`, toward gone when `false`.
  final bool entering;

  /// The frame the leg starts from: the previous leg's current frame on a
  /// reversal.
  final ChatRowChromeTransitionFrame from;

  /// Ticker elapsed time of the frame that registered the leg.
  final Duration start;

  /// The frame as of the latest tick.
  ChatRowChromeTransitionFrame frame;

  /// The frame [elapsed] into the leg, or `null` once the leg is done.
  ///
  /// The extent follows the list-item change timing. An
  /// enter fades and scales in over [kChatRowChromeEnterDuration]; an exit
  /// fades out over [kChatRowChromeExitFadeDuration] and brings any
  /// leftover scale back to `1` with it. The leg ends with the longest
  /// track.
  ChatRowChromeTransitionFrame? frameAt(Duration elapsed) {
    double progress(Duration duration) =>
        (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
    final move = progress(kChatMessageChangeDuration);
    final fade = progress(
      entering ? kChatRowChromeEnterDuration : kChatRowChromeExitFadeDuration,
    );
    if (move >= 1 && fade >= 1) return null;
    final moved = kChatMessageChangeCurve.transform(move);
    final faded = _fadeCurve.transform(fade);
    return ChatRowChromeTransitionFrame(
      extent: lerpDouble(from.extent, entering ? 1 : 0, moved)!,
      opacity: lerpDouble(from.opacity, entering ? 1 : 0, faded)!,
      scale: lerpDouble(from.scale, 1, faded)!,
    );
  }
}

/// Per-row clock for row chrome that enters and exits: one leg per row id,
/// all driven by one [Ticker].
///
/// ## Legs
///
/// [enter] runs a row's item toward [ChatRowChromeTransitionFrame.settled];
/// [exit] runs it toward nothing (extent and opacity `0`). A call that
/// reverses a running leg starts the new leg from the current frame, with
/// the full duration, so the item never jumps. A call that repeats the
/// running direction is a no-op. A leg ends when its last track does; the
/// row then has no frame ([frameOf] is `null`) — settled after an enter,
/// removed after an exit.
///
/// Legs start on the frame that registers them: the first frame of a leg is
/// its start frame, and time runs from that frame's timestamp.
///
/// ## Change reporting
///
/// Frames move inside ticker callbacks, and [onChanged] fires there. The ids
/// whose frame moved or ended collect until [takeChanged]; ids that
/// [enter], [exit], [cancel], or a mute touched are collected as well. The
/// owner lays out on [onChanged] and reads [frameOf] per row.
///
/// ## Mute
///
/// While [muted] (the host's `TickerMode` is off), no leg runs: muting ends
/// every leg at once, and [enter] / [exit] only cancel.
///
/// Not an `AnimationController`: the owner is a render object with no
/// `TickerProvider`.
@internal
final class ChatRowChromeTransitionClock {
  /// A clock with no legs.
  ChatRowChromeTransitionClock({required VoidCallback onChanged})
    : _onChanged = onChanged {
    _ticker = Ticker(_tick, debugLabel: 'ChatRowChromeTransitionClock');
  }

  final VoidCallback _onChanged;
  late final Ticker _ticker;
  final Map<int, _Leg> _legs = <int, _Leg>{};
  final Set<int> _changed = <int>{};
  Duration _elapsed = Duration.zero;
  bool _muted = false;

  /// The current frame of row [id], or `null` when it has no running leg.
  ChatRowChromeTransitionFrame? frameOf(int id) => _legs[id]?.frame;

  /// Whether row [id] runs an exit leg: its item stays built until the leg
  /// ends.
  bool isExiting(int id) => _legs[id]?.entering == false;

  /// Runs row [id]'s item in: from the current frame when an exit is
  /// running, from [ChatRowChromeTransitionFrame.hidden] otherwise.
  void enter(int id) => _run(id, entering: true);

  /// Runs row [id]'s item out: from the current frame when an enter is
  /// running, from [ChatRowChromeTransitionFrame.settled] otherwise.
  void exit(int id) => _run(id, entering: false);

  void _run(int id, {required bool entering}) {
    final leg = _legs[id];
    if (leg?.entering == entering) return;
    if (_muted) {
      cancel(id);
      return;
    }
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
    _legs[id] = _Leg(
      entering: entering,
      from:
          leg?.frame ??
          (entering
              ? ChatRowChromeTransitionFrame.hidden
              : ChatRowChromeTransitionFrame.settled),
      start: _elapsed,
    );
    _changed.add(id);
  }

  /// Ends row [id]'s leg without animating. No-op without a leg.
  void cancel(int id) {
    if (_legs.remove(id) == null) return;
    _changed.add(id);
    if (_legs.isEmpty) _ticker.stop();
  }

  /// Ends, without reporting, the legs of every row [keep] rejects — rows
  /// the owner no longer builds.
  void retainWhere(bool Function(int id) keep) {
    _legs.removeWhere((id, _) => !keep(id));
    if (_legs.isEmpty) _ticker.stop();
  }

  /// Returns and clears the ids whose frame changed since the previous call.
  Set<int> takeChanged() {
    if (_changed.isEmpty) return const <int>{};
    final changed = Set<int>.of(_changed);
    _changed.clear();
    return changed;
  }

  /// While `true` no leg runs. Muting ends every running leg and fires
  /// [onChanged] synchronously when there was one, so set it outside the
  /// owner's layout and paint (the viewport sets it from
  /// `updateRenderObject`).
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (!value || _legs.isEmpty) return;
    _changed.addAll(_legs.keys);
    _legs.clear();
    _ticker.stop();
    _onChanged();
  }

  /// Advances every leg to [elapsed], drops finished legs, stops the ticker
  /// when none remain, and fires [onChanged] once when any frame moved or
  /// ended.
  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    var changed = false;
    final done = <int>[];
    for (final MapEntry(key: id, value: leg) in _legs.entries) {
      final next = leg.frameAt(elapsed - leg.start);
      if (next == null) {
        done.add(id);
      } else if (next != leg.frame) {
        leg.frame = next;
      } else {
        continue;
      }
      _changed.add(id);
      changed = true;
    }
    done.forEach(_legs.remove);
    if (_legs.isEmpty) _ticker.stop();
    if (changed) _onChanged();
  }

  /// Disposes the ticker. The clock must not be used afterwards.
  void dispose() => _ticker.dispose();
}
