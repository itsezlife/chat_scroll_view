import 'dart:async';
import 'dart:ui' as ui;

import 'package:chrome_foundation/src/backdrop/backdrop_snapshot.dart';
import 'package:chrome_foundation/src/backdrop/chrome_scrim_preset.dart';
import 'package:chrome_foundation/src/menu/overlay_back_button_listener.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What closed a chrome scrim from outside its owner.
enum ChromeScrimDismissal {
  /// A press outside the surface.
  outside,

  /// The system back.
  back,

  /// The Escape key, where the preset closes on it.
  escape,
}

/// Why a chrome scrim has no still.
enum ChromeScrimStillSkip {
  /// The preset is a dim alone.
  presetNoBlur,

  /// No `BackdropSnapshotSource` is above the owner, or it has not painted.
  noSource,

  /// The platform's reduce-transparency setting is on.
  reduceTransparency,
}

/// A step of a chrome scrim's life, told to its owner with its numbers.
///
/// The scrim reports and never logs: its owner turns these into its own
/// events.
sealed class ChromeScrimPhase {
  const ChromeScrimPhase();

  /// The window was captured.
  const factory ChromeScrimPhase.captured({
    required Duration captureTime,
    required ui.Size stillSize,
  }) = ChromeScrimPhase$Captured;

  /// The still was made from the capture.
  const factory ChromeScrimPhase.stillReady({required Duration makeTime}) =
      ChromeScrimPhase$StillReady;

  /// The scrim has no still.
  const factory ChromeScrimPhase.stillSkipped(ChromeScrimStillSkip why) =
      ChromeScrimPhase$StillSkipped;

  /// A press outside, back or Escape closed the scrim.
  const factory ChromeScrimPhase.dismissed({
    required ChromeScrimDismissal by,
    required ChromeScrimCloseOn closeOn,
  }) = ChromeScrimPhase$Dismissed;

  /// The scrim was cancelled: taken away without a fade.
  const factory ChromeScrimPhase.cancelled() = ChromeScrimPhase$Cancelled;

  /// The scrim let go of its stills: its fade out ended, it was cancelled,
  /// or it was removed.
  const factory ChromeScrimPhase.disposed({required int stills}) =
      ChromeScrimPhase$Disposed;

  /// The capture threw, or its still could not be made.
  const factory ChromeScrimPhase.captureFailed(Object error) =
      ChromeScrimPhase$CaptureFailed;
}

/// The window was captured, in [captureTime], at [stillSize] pixels.
final class ChromeScrimPhase$Captured extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.captured].
  const ChromeScrimPhase$Captured({
    required this.captureTime,
    required this.stillSize,
  });

  /// How long the capture took, on the UI thread.
  final Duration captureTime;

  /// The still's size in pixels.
  final ui.Size stillSize;
}

/// The still was made, [makeTime] after the capture.
final class ChromeScrimPhase$StillReady extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.stillReady].
  const ChromeScrimPhase$StillReady({required this.makeTime});

  /// From the capture to the still being made: reading its pixels, the blur
  /// and the tone (off the UI isolate where there is another), the decode.
  final Duration makeTime;
}

/// The scrim has no still, for [why].
final class ChromeScrimPhase$StillSkipped extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.stillSkipped].
  const ChromeScrimPhase$StillSkipped(this.why);

  /// Why there is no still.
  final ChromeScrimStillSkip why;
}

/// The scrim was closed [by] a press outside, back or Escape.
final class ChromeScrimPhase$Dismissed extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.dismissed].
  const ChromeScrimPhase$Dismissed({required this.by, required this.closeOn});

  /// What closed it.
  final ChromeScrimDismissal by;

  /// When a press outside closes the scrim, by its preset.
  final ChromeScrimCloseOn closeOn;
}

/// The scrim was cancelled.
final class ChromeScrimPhase$Cancelled extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.cancelled].
  const ChromeScrimPhase$Cancelled();
}

/// The scrim let go of [stills] stills.
final class ChromeScrimPhase$Disposed extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.disposed].
  const ChromeScrimPhase$Disposed({required this.stills});

  /// How many stills it disposed.
  final int stills;
}

/// The capture failed with [error].
final class ChromeScrimPhase$CaptureFailed extends ChromeScrimPhase {
  /// See [ChromeScrimPhase.captureFailed].
  const ChromeScrimPhase$CaptureFailed(this.error);

  /// What was thrown, or a [StateError] when the still was never made.
  final Object error;
}

/// One chrome scrim's life: its still, what it shows, its closing.
///
/// An owner (an overlay, a preview) opens one per surface it brings up over
/// the whole window, between frames, before the surface paints, and builds a
/// [ChromeScrim] over it with the surface as its child. A second surface
/// opened over the first takes a scrim of its own.
///
/// The controller owns its still and disposes it when its fade out ends, on
/// [cancel], or when its [ChromeScrim] is removed without either: an owner
/// never disposes it.
final class ChromeScrimController implements Listenable {
  /// Opens a scrim of [preset] over the window of [context], capturing the
  /// window now: called between frames, before the surface paints, the
  /// still is of the window without it.
  ///
  /// - [showStill]: whether the still fades in as soon as it is made; when
  ///   false it waits for [showStill]'s call (a still on a clock of its own).
  /// - [reduceTransparency]: the host's reduce-transparency setting; on, the
  ///   scrim takes no still and draws its dim alone.
  /// - [onPhase]: told each phase once, in order; the first ones (captured,
  ///   or still skipped) during this constructor.
  /// - [onDismiss]: told when a press outside, back or Escape closes the
  ///   scrim, after it starts closing; the owner closes its surface with it.
  ChromeScrimController(
    BuildContext context, {
    required this.preset,
    bool showStill = true,
    this.reduceTransparency = false,
    ValueChanged<ChromeScrimPhase>? onPhase,
    ValueChanged<ChromeScrimDismissal>? onDismiss,
  }) : _stillShown = showStill,
       _onPhase = onPhase,
       _onDismiss = onDismiss,
       _backDispatcher = Router.maybeOf(context)?.backButtonDispatcher {
    _still = _capture(context);
  }

  /// How the scrim looks and closes.
  final ChromeScrimPreset preset;

  /// Whether the scrim was opened without a still for the host's
  /// reduce-transparency setting.
  final bool reduceTransparency;

  final ValueChanged<ChromeScrimPhase>? _onPhase;
  final ValueChanged<ChromeScrimDismissal>? _onDismiss;
  final BackButtonDispatcher? _backDispatcher;
  final _ScrimChanges _changes = _ScrimChanges();
  final Completer<void> _done = Completer<void>();
  BackdropSnapshot? _still;
  bool _stillShown;
  bool _closing = false;
  int _views = 0;

  /// The still under the dim, or null (see [ChromeScrimStillSkip]); its
  /// image is null until it is made.
  BackdropSnapshot? get still => _still;

  /// Whether the still is to be shown (once made).
  bool get isStillShown => _stillShown;

  /// Whether the scrim is closing or done: it no longer takes presses.
  bool get isClosing => _closing;

  /// Whether the scrim is gone: faded out, cancelled or removed.
  bool get isDone => _done.isCompleted;

  /// Completes once the scrim is gone and its stills are disposed.
  Future<void> get done => _done.future;

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  BackdropSnapshot? _capture(BuildContext context) {
    final still = preset.still;
    if (still == null) {
      _report(
        const ChromeScrimPhase.stillSkipped(ChromeScrimStillSkip.presetNoBlur),
      );
      return null;
    }
    if (reduceTransparency) {
      _report(
        const ChromeScrimPhase.stillSkipped(
          ChromeScrimStillSkip.reduceTransparency,
        ),
      );
      return null;
    }
    final palette = ChromeThemeScope.paletteOf(context);
    final window = View.maybeOf(context)?.physicalSize ?? ui.Size.zero;
    final watch = Stopwatch()..start();
    final BackdropSnapshot? captured;
    try {
      captured = BackdropSnapshot.capture(
        context,
        downscale: still.downscale,
        blurRadius: still.radiusFor(window),
        tone: still.toneFor(palette.brightness)?.matrix,
        // Where the window painted nothing: its base fill.
        background: palette.surface,
      );
    } on Object catch (error) {
      _report(ChromeScrimPhase.captureFailed(error));
      return null;
    }
    final snapshot = switch (captured) {
      final snapshot? => snapshot,
      null => null,
    };
    if (snapshot == null) {
      _report(
        const ChromeScrimPhase.stillSkipped(ChromeScrimStillSkip.noSource),
      );
      return null;
    }
    _report(
      ChromeScrimPhase.captured(
        captureTime: watch.elapsed,
        stillSize: ui.Size(
          snapshot.width.toDouble(),
          snapshot.height.toDouble(),
        ),
      ),
    );
    watch.reset();
    unawaited(
      snapshot.ready.then((_) {
        if (snapshot.isDisposed) return;
        _report(
          snapshot.image == null
              ? ChromeScrimPhase.captureFailed(
                  StateError('The still could not be made.'),
                )
              : ChromeScrimPhase.stillReady(makeTime: watch.elapsed),
        );
      }),
    );
    return snapshot;
  }

  void _report(ChromeScrimPhase phase) => _onPhase?.call(phase);

  /// Brings the still in, on its own clock, once it is made.
  void showStill() {
    if (_stillShown) return;
    _stillShown = true;
    _changes.notify();
  }

  /// Takes the still out, on its own clock; the dim stays.
  void hideStill() {
    if (!_stillShown) return;
    _stillShown = false;
    _changes.notify();
  }

  /// Fades the scrim out, dim and still each on its clock, then disposes
  /// its stills and completes [done]. Further calls do nothing.
  void close() {
    if (_closing) return;
    _closing = true;
    // Never built: nothing to fade.
    if (_views == 0) {
      _finish();
      return;
    }
    _changes.notify();
  }

  /// Takes the scrim away at once, without a fade, and disposes its stills.
  /// Does nothing once it is done.
  void cancel() {
    if (isDone) return;
    _closing = true;
    _report(const ChromeScrimPhase.cancelled());
    _finish();
  }

  void _dismiss(ChromeScrimDismissal by) {
    if (_closing) return;
    _report(ChromeScrimPhase.dismissed(by: by, closeOn: preset.closeOn));
    close();
    _onDismiss?.call(by);
  }

  // The fade out ended, it was cancelled, or its view went.
  void _finish() {
    if (isDone) return;
    _closing = true;
    // Done first: disposing the still notifies its view, which reads this.
    _done.complete();
    var stills = 0;
    if (_still case final still?) {
      still.dispose();
      stills++;
    }
    _report(ChromeScrimPhase.disposed(stills: stills));
    _changes.notify();
  }
}

final class _ScrimChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// A chrome scrim over the whole window, under [child], the surface.
///
/// Draws its controller's still, once made, under the preset's dim, both
/// faded by opacity alone (the still by its paint's alpha, the dim by its
/// colour's: no opacity layer, no backdrop filter), each on its own clock. A
/// press outside the child closes it on the preset's `closeOn`, and goes no
/// further; back closes it, and Escape where the preset says. Once its
/// controller is done it draws nothing, the child included.
///
/// The scrim draws no text; a surface on it puts its own text root.
class ChromeScrim extends StatefulWidget {
  /// A scrim of [controller] under [child].
  const ChromeScrim({required this.controller, required this.child, super.key});

  /// The scrim's life: its still, what it shows, its closing.
  final ChromeScrimController controller;

  /// The surface over the scrim. Where it does not take a press, the press
  /// lands on the scrim.
  final Widget child;

  @override
  State<ChromeScrim> createState() => _ChromeScrimState();
}

class _ChromeScrimState extends State<ChromeScrim>
    with TickerProviderStateMixin {
  late final AnimationController _dim = AnimationController(
    vsync: this,
    duration: _preset.dimFade.duration,
  );
  late final AnimationController _still = AnimationController(
    vsync: this,
    duration: _preset.stillFade.duration,
  );
  late final CurvedAnimation _dimEased = CurvedAnimation(
    parent: _dim,
    curve: _preset.dimFade.curve,
  );
  late final CurvedAnimation _stillEased = CurvedAnimation(
    parent: _still,
    curve: _preset.stillFade.curve,
  );
  // The pointer that went down on the scrim, for a close on lift.
  int? _pressed;

  ChromeScrimController get _controller => widget.controller;
  ChromeScrimPreset get _preset => _controller.preset;

  @override
  void initState() {
    super.initState();
    _attach(_controller);
    _dim.addStatusListener(_onFaded);
    _still.addStatusListener(_onFaded);
    unawaited(_dim.forward());
    _sync();
  }

  @override
  void didUpdateWidget(ChromeScrim oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.controller, widget.controller),
      'A ChromeScrim keeps its controller; a new scrim takes a new widget.',
    );
  }

  @override
  void dispose() {
    _detach(_controller);
    _dimEased.dispose();
    _stillEased.dispose();
    _dim.dispose();
    _still.dispose();
    super.dispose();
  }

  void _attach(ChromeScrimController controller) {
    controller._views++;
    controller.addListener(_sync);
    controller._still?.addListener(_sync);
  }

  void _detach(ChromeScrimController controller) {
    controller.removeListener(_sync);
    controller._still?.removeListener(_sync);
    // Removed without a close or a cancel: nothing is left to show it.
    if (--controller._views == 0) controller._finish();
  }

  // Drives both clocks toward what the controller wants now.
  void _sync() {
    if (!mounted) return;
    final controller = _controller;
    if (controller.isDone) {
      setState(() {});
      return;
    }
    if (controller.isClosing) {
      unawaited(_dim.reverse());
      unawaited(_still.reverse());
      setState(() {});
      _onFaded(AnimationStatus.dismissed);
      return;
    }
    final made = controller._still?.image != null;
    if (controller.isStillShown && made) {
      unawaited(_still.forward());
    } else {
      unawaited(_still.reverse());
    }
    // The view stands while the still is wanted, made or not.
    setState(() {});
  }

  void _onFaded(AnimationStatus _) {
    if (_controller.isClosing && _dim.isDismissed && _still.isDismissed) {
      _controller._finish();
    }
  }

  Future<bool> _onBack() async {
    _controller._dismiss(ChromeScrimDismissal.back);
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _controller._dismiss(ChromeScrimDismissal.escape);
    return KeyEventResult.handled;
  }

  void _onDown(PointerDownEvent event) {
    switch (_preset.closeOn) {
      case ChromeScrimCloseOn.down:
        _controller._dismiss(ChromeScrimDismissal.outside);
      case ChromeScrimCloseOn.up:
        _pressed = event.pointer;
    }
  }

  void _onUp(PointerUpEvent event) {
    if (_pressed != event.pointer) return;
    _pressed = null;
    _controller._dismiss(ChromeScrimDismissal.outside);
  }

  void _onCancel(PointerCancelEvent event) {
    if (_pressed == event.pointer) _pressed = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller.isDone) return const SizedBox.shrink();
    final dim = _preset.dimFor(ChromeThemeScope.paletteOf(context).brightness);
    final strength = dim.a * 255 * _preset.dimOpacity;
    Widget scrim = Stack(
      fit: StackFit.expand,
      children: [
        // The view stands from the moment the still is wanted, before it
        // is made: it draws nothing until then, and an owner finds the
        // still it asked for in the tree at once.
        if (controller.still case final still?)
          AnimatedBuilder(
            animation: _still,
            builder: (context, _) =>
                _still.isDismissed &&
                    !(controller.isStillShown && !controller.isClosing)
                ? const SizedBox.expand()
                : BackdropSnapshotView(snapshot: still, opacity: _stillEased),
          ),
        AnimatedBuilder(
          animation: _dimEased,
          builder: (context, _) => ColoredBox(
            color: dim.withAlpha((strength * _dimEased.value).round()),
          ),
        ),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
        ),
        widget.child,
      ],
    );
    if (_preset.closesOnEscape) {
      scrim = Focus(autofocus: true, onKeyEvent: _onKey, child: scrim);
    }
    return IgnorePointer(
      ignoring: controller.isClosing,
      child: OverlayBackButtonListener(
        parentDispatcher: controller._backDispatcher,
        onBackButtonPressed: _onBack,
        child: scrim,
      ),
    );
  }
}
