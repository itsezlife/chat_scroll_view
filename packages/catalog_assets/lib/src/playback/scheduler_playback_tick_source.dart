import 'package:catalog_assets/src/playback/playback_tick_source.dart';
import 'package:flutter/scheduler.dart';

/// The production [PlaybackTickSource]: one frame callback per frame on the
/// [SchedulerBinding], requested only while started.
final class SchedulerPlaybackTickSource implements PlaybackTickSource {
  void Function(Duration timestamp)? _onTick;
  int? _callbackId;

  @override
  void start(void Function(Duration timestamp) onTick) {
    if (_onTick != null) return;
    _onTick = onTick;
    _request(rescheduling: false);
  }

  @override
  void stop() {
    _onTick = null;
    final id = _callbackId;
    if (id != null) {
      _callbackId = null;
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
  }

  void _request({required bool rescheduling}) {
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(
      _onFrame,
      rescheduling: rescheduling,
    );
  }

  void _onFrame(Duration timestamp) {
    _callbackId = null;
    final onTick = _onTick;
    if (onTick == null) return;
    // Request the next frame first: the tick may stop the source.
    _request(rescheduling: true);
    onTick(timestamp);
  }
}
