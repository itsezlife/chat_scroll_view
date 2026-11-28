import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// What the user points with, in two classes a web policy takes its
/// interaction from: hover or tap, long press, row density.
///
/// The class starts from the browser's operating system ([forPlatform]: a
/// phone or tablet system is [touch]) and, under a [ChromeInputClassScope],
/// follows the pointer kind of the last pointer event ([fromPointerKind]),
/// so a touchscreen laptop is [mouse] while the mouse moves and [touch]
/// after a tap. It is the other axis to `ChromeWidthClass`: a desktop
/// window narrowed to a phone's width stays [mouse].
///
/// A decision made per gesture (hover or tap, double click or swipe) reads
/// the kind of that gesture's own event through [fromPointerKind], not the
/// class of the window, so it is right even on the first event of a new
/// device.
///
/// The web is the reader this is written for. A host may hand it to any
/// platform's policy; nothing in the package picks a policy from it.
enum ChromeInputClass {
  /// A finger or a pen: no hover, taps and long presses, roomy rows.
  touch,

  /// A mouse or a trackpad: hover, clicks, compact rows.
  mouse;

  /// The class an operating system starts at: [touch] on Android and iOS,
  /// [mouse] elsewhere.
  ///
  /// On the web the platform is the browser's operating system, so a phone
  /// browser starts at [touch] and a desktop browser at [mouse].
  static ChromeInputClass forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android || TargetPlatform.iOS => touch,
        TargetPlatform.fuchsia ||
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => mouse,
      };

  /// The class of a pointer of [kind], or null for a kind that says nothing
  /// ([PointerDeviceKind.unknown]), which leaves the class as it was.
  ///
  /// A pen counts as [touch]: it does not hover where a policy would rely on
  /// it, and it presses like a finger.
  static ChromeInputClass? fromPointerKind(PointerDeviceKind kind) =>
      switch (kind) {
        PointerDeviceKind.touch ||
        PointerDeviceKind.stylus ||
        PointerDeviceKind.invertedStylus => touch,
        PointerDeviceKind.mouse || PointerDeviceKind.trackpad => mouse,
        PointerDeviceKind.unknown => null,
      };

  /// The class at [context]: the nearest [ChromeInputClassScope]'s live
  /// value, or, without a scope, [forPlatform] of the running platform,
  /// fixed for the run.
  ///
  /// Depends on the scope, so a reader rebuilds when the class changes and
  /// not on every pointer event.
  static ChromeInputClass of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ChromeInputClassMark>()
          ?.inputClass ??
      forPlatform(defaultTargetPlatform);

  /// Whether this is [touch].
  bool get isTouch => this == touch;
}

/// Makes [ChromeInputClass.of] follow the pointer in [child].
///
/// The scope listens to every pointer event the app receives, wherever it
/// lands, not only those over [child]: the class is the user's, and a menu
/// opened from a strip must know a mouse moved elsewhere. One scope near the
/// root is enough; a nested one tracks the same events.
///
/// Without a scope the class stays at the platform's ([forPlatform]), which
/// is what a host that never mixes inputs needs.
class ChromeInputClassScope extends StatefulWidget {
  /// Tracks the pointer for [child], starting at [initial] (the platform's
  /// class when null).
  const ChromeInputClassScope({required this.child, this.initial, super.key});

  /// The class before the first pointer event; the platform's when null.
  /// Read once, when the scope is first built.
  final ChromeInputClass? initial;

  /// The subtree that reads the class.
  final Widget child;

  @override
  State<ChromeInputClassScope> createState() => _ChromeInputClassScopeState();
}

class _ChromeInputClassScopeState extends State<ChromeInputClassScope> {
  late ChromeInputClass _inputClass =
      widget.initial ?? ChromeInputClass.forPlatform(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    // A global route, not a `Listener`: a `Listener` hears only events that
    // hit its subtree, and the class must follow the pointer anywhere.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerEvent);
    super.dispose();
  }

  void _onPointerEvent(PointerEvent event) {
    // Added and removed events announce a device, not its use: a mouse
    // plugged in beside a touchscreen has not been moved yet.
    if (event case PointerAddedEvent() || PointerRemovedEvent()) return;
    final next = ChromeInputClass.fromPointerKind(event.kind);
    if (next == null || next == _inputClass) return;
    setState(() => _inputClass = next);
  }

  @override
  Widget build(BuildContext context) =>
      _ChromeInputClassMark(inputClass: _inputClass, child: widget.child);
}

class _ChromeInputClassMark extends InheritedWidget {
  const _ChromeInputClassMark({required this.inputClass, required super.child});

  final ChromeInputClass inputClass;

  @override
  bool updateShouldNotify(_ChromeInputClassMark oldWidget) =>
      inputClass != oldWidget.inputClass;
}
