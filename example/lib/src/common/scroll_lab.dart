import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatScrollController, ChatScrollEvent, ChatViewportScrolled;
import 'package:chat_scroll_view/experiments.dart';
import 'package:chat_scroll_view_example/src/common/lab_net.dart';
import 'package:chat_scroll_view_example/src/common/pointer_tape.dart';
import 'package:chat_scroll_view_example/src/common/tape_system_events.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Scroll-smoothness lab: runtime switches to A/B on a device, and a frame
/// log in logcat (`adb logcat -s flutter | grep LAB`).
///
/// Each scroll burst (frames until 400 ms of quiet) prints one `LAB burst`
/// line; a frame over budget also prints a `LAB slow` line with its phases.
abstract final class ScrollLab {
  /// `GestureBinding.resamplingEnabled`: pointer samples resampled to the
  /// frame time, as the platform's input pipeline does.
  static final resampling = ValueNotifier<bool>(false);

  /// [ChatScrollExperiments.snapRowsToPhysicalPixels].
  static final pixelSnap = ValueNotifier<bool>(false);

  /// Message bodies as a plain [Text] of the raw markdown instead of the
  /// markdown engine.
  static final plainText = ValueNotifier<bool>(false);

  static const _channel = MethodChannel('chat_scroll_view_example/lab');

  static bool _installed = false;

  /// Installs the frame log and wires the switches. Idempotent.
  static void install() {
    if (_installed) return;
    _installed = true;
    resampling.addListener(() {
      GestureBinding.instance.resamplingEnabled = resampling.value;
      _log('switch resampling=${resampling.value}');
    });
    pixelSnap.addListener(() {
      ChatScrollExperiments.snapRowsToPhysicalPixels = pixelSnap.value;
      _log('switch pixelSnap=${pixelSnap.value}');
    });
    plainText.addListener(() => _log('switch plainText=${plainText.value}'));
    PointerTape.install();
    TapeSystemRecorder.install();
    final net = LabNet.instance = LabNet(
      filesDir: () async => (await _channel.invokeMethod<String>('filesDir'))!,
    );
    // The mode a launcher left in `net_mode.txt`, in force before the first
    // Giphy request of a cold start.
    unawaited(net.loadPersisted());
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'set') return;
      final args = call.arguments as Map<Object?, Object?>;
      final name = (args['name'] as String?) ?? 'tape';
      switch (args['key']) {
        case 'record' when args['value'] == true:
          PointerTape.start();
          await net.select(LabNetMode.record, name);
          _log('tape record start $name');
          return;
        case 'record':
          final dir = await _channel.invokeMethod<String>('filesDir');
          final n = await PointerTape.stop(dir!, name);
          await net.select(LabNetMode.off, name);
          _log('tape saved $name events=$n');
          return;
        case 'animate':
          // A scroll no finger started, as the jump to a new message is:
          // `--es name <messages>` back from the anchor (30 by default).
          if (_watched case final controller?) {
            final by = int.tryParse(name) ?? 30;
            _log('animate by $by');
            unawaited(
              controller.animateTo(
                controller.anchorMessageId - by,
                duration: const Duration(milliseconds: 600),
                highlight: false,
              ),
            );
          }
          return;
        case 'net':
          final mode = LabNetMode.values.asNameMap()[args['text']];
          if (mode == null) {
            _log('net: value must be off|record|replay');
          } else {
            await net.select(mode, name);
          }
          return;
        case 'replay':
          final dir = await _channel.invokeMethod<String>('filesDir');
          await net.select(LabNetMode.replay, name);
          _log('tape replay start $name');
          _replayFrames = [];
          final n = await PointerTape.replay(
            dir!,
            name,
            system: dispatchTapeSystemEvent,
          );
          // Timings arrive in batches; let the last one land.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          _logReplaySummary(_replayFrames!);
          _replayFrames = null;
          net.logSummary();
          _log('tape replay done $name events=$n');
          return;
      }
      final target = switch (args['key']) {
        'resampling' => resampling,
        'snap' => pixelSnap,
        'plain' => plainText,
        _ => null,
      };
      target?.value = args['value'] == true;
    });
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static int get _budgetMicros {
    final hz =
        WidgetsBinding
            .instance
            .platformDispatcher
            .displays
            .firstOrNull
            ?.refreshRate ??
        60;
    return (1e6 / hz).round();
  }

  static final _burst = <FrameTiming>[];
  static Timer? _quiet;

  static List<FrameTiming>? _replayFrames;

  static void _logReplaySummary(List<FrameTiming> frames) {
    if (frames.isEmpty) return;
    final budget = _budgetMicros;
    final build = [for (final t in frames) t.buildDuration.inMicroseconds]
      ..sort();
    final raster = [for (final t in frames) t.rasterDuration.inMicroseconds]
      ..sort();
    String q(List<int> v) =>
        '${_ms(_p(v, .5))}/${_ms(_p(v, .9))}/${_ms(_p(v, .99))}/${_ms(v.last)}';
    var gaps = 0;
    for (var i = 1; i < frames.length; i++) {
      final dt =
          frames[i].timestampInMicroseconds(FramePhase.vsyncStart) -
          frames[i - 1].timestampInMicroseconds(FramePhase.vsyncStart);
      if (dt > budget * 1.5 && dt < 100000) gaps++;
    }
    _log(
      'summary frames=${frames.length} '
      'build p50/p90/p99/max=${q(build)} '
      'build>5=${build.where((b) => b > 5000).length} '
      'build>8.3=${build.where((b) => b > budget).length} '
      'raster p50/p90/p99/max=${q(raster)} '
      'vsyncGaps=$gaps',
    );
  }

  static void _onTimings(List<FrameTiming> timings) {
    _replayFrames?.addAll(timings);
    final budget = _budgetMicros;
    for (final t in timings) {
      _burst.add(t);
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      if (t.totalSpan.inMicroseconds > budget) {
        _log(
          'slow #${t.frameNumber} span=${_ms(t.totalSpan.inMicroseconds)} '
          'vsync=${_ms(t.vsyncOverhead.inMicroseconds)} '
          'build=${_ms(build)} raster=${_ms(raster)} '
          'queue=${_ms(t.timestampInMicroseconds(FramePhase.rasterStart) - t.timestampInMicroseconds(FramePhase.buildFinish))}',
        );
      }
    }
    _quiet?.cancel();
    _quiet = Timer(const Duration(milliseconds: 400), _flushBurst);
  }

  static void _flushBurst() {
    if (_burst.length < 10) {
      _burst.clear();
      return;
    }
    final budget = _budgetMicros;
    final spans = [for (final t in _burst) t.totalSpan.inMicroseconds]..sort();
    final builds = [for (final t in _burst) t.buildDuration.inMicroseconds]
      ..sort();
    final rasters = [for (final t in _burst) t.rasterDuration.inMicroseconds]
      ..sort();
    final over = spans.where((s) => s > budget).length;
    // Gaps between consecutive vsyncs over 1.5 budgets: frames the display
    // repeated, whatever their own phases say.
    var gaps = 0;
    for (var i = 1; i < _burst.length; i++) {
      final dt =
          _burst[i].timestampInMicroseconds(FramePhase.vsyncStart) -
          _burst[i - 1].timestampInMicroseconds(FramePhase.vsyncStart);
      if (dt > budget * 1.5) gaps++;
    }
    _log(
      'burst frames=${_burst.length} over=$over gaps=$gaps '
      'build p50/p99/max=${_ms(_p(builds, .5))}/${_ms(_p(builds, .99))}/${_ms(builds.last)} '
      'raster p50/p99/max=${_ms(_p(rasters, .5))}/${_ms(_p(rasters, .99))}/${_ms(rasters.last)} '
      'span max=${_ms(spans.last)} '
      '[resampling=${resampling.value} snap=${pixelSnap.value} '
      'plain=${plainText.value}]',
    );
    _burst.clear();
  }

  static int _p(List<int> sorted, double q) =>
      sorted[((sorted.length - 1) * q).round()];

  static String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

  static void _log(String message) => debugPrint('LAB $message');

  static double _scrolled = 0;

  static ChatScrollController? _watched;

  /// Marks where the content stands on every frame [controller] scrolls, as a
  /// `LABy <px>` timeline slice inside that frame, so a trace pairs each
  /// presented frame with its content position. No-op unless installed.
  static void watch(ChatScrollController controller) {
    if (!_installed) return;
    _watched = controller;
    controller.addScrollListener(_onScroll);
  }

  static void _onScroll(ChatScrollEvent event) {
    if (event case ChatViewportScrolled(:final delta)) {
      _scrolled += delta;
      Timeline.timeSync('LABy ${_scrolled.toStringAsFixed(2)}', () {});
    }
  }
}

/// A small chip in the top-right corner that unfolds the lab switches.
/// Mounted above the navigator, so the switches unfold in place rather than
/// in a route.
class ScrollLabOverlay extends StatefulWidget {
  /// Wraps [child] with the lab chip.
  const ScrollLabOverlay({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  State<ScrollLabOverlay> createState() => _ScrollLabOverlayState();
}

class _ScrollLabOverlayState extends State<ScrollLabOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned(
        top: MediaQuery.paddingOf(context).top + 4,
        right: 72,
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'LAB',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
              if (_open)
                SizedBox(
                  width: 240,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toggle('Input resampling', ScrollLab.resampling),
                      _toggle('Pixel snap rows', ScrollLab.pixelSnap),
                      _toggle('Plain text bodies', ScrollLab.plainText),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _toggle(String title, ValueNotifier<bool> value) =>
      ValueListenableBuilder<bool>(
        valueListenable: value,
        builder: (context, on, _) => SwitchListTile(
          dense: true,
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
          value: on,
          onChanged: (v) => value.value = v,
        ),
      );
}
