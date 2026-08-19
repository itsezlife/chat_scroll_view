import 'package:flutter/widgets.dart';

/// System-back handler for content shown in a root [Overlay].
///
/// Prefer this over [BackButtonListener] when the child is built inside a
/// root [OverlayEntry] that is not under [Router]. [BackButtonListener]
/// calls [Router.of] on its own context and throws in that case.
///
/// Capture [parentDispatcher] from a context that *is* under [Router]
/// before inserting the overlay entry. When [parentDispatcher] is null
/// (classic [MaterialApp] without a [Router]), falls back to
/// [WidgetsBindingObserver.didPopRoute].
class OverlayBackButtonListener extends StatefulWidget {
  /// Registers [onBackButtonPressed] with a child of [parentDispatcher].
  const OverlayBackButtonListener({
    required this.onBackButtonPressed,
    required this.child,
    this.parentDispatcher,
    super.key,
  });

  /// Root dispatcher from [Router.backButtonDispatcher], or `null` to
  /// use the [WidgetsBindingObserver] fallback.
  final BackButtonDispatcher? parentDispatcher;

  /// Invoked when the system back button is pressed.
  ///
  /// Return `true` if this listener handled the event (keyboard / route
  /// should stay).
  final ValueGetter<Future<bool>> onBackButtonPressed;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<OverlayBackButtonListener> createState() =>
      _OverlayBackButtonListenerState();
}

class _OverlayBackButtonListenerState extends State<OverlayBackButtonListener>
    with WidgetsBindingObserver {
  BackButtonDispatcher? _dispatcher;
  var _observingPop = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.parentDispatcher, widget.onBackButtonPressed);
  }

  @override
  void didUpdateWidget(covariant OverlayBackButtonListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentDispatcher != widget.parentDispatcher ||
        oldWidget.onBackButtonPressed != widget.onBackButtonPressed) {
      _detach(oldWidget.onBackButtonPressed);
      _attach(widget.parentDispatcher, widget.onBackButtonPressed);
    }
  }

  @override
  void dispose() {
    _detach(widget.onBackButtonPressed);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() {
    if (!_observingPop) return Future<bool>.value(false);
    return widget.onBackButtonPressed();
  }

  void _attach(
    BackButtonDispatcher? parent,
    ValueGetter<Future<bool>> callback,
  ) {
    if (parent != null) {
      _dispatcher = parent.createChildBackButtonDispatcher()
        ..addCallback(callback)
        ..takePriority();
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observingPop = true;
  }

  void _detach(ValueGetter<Future<bool>> callback) {
    _dispatcher?.removeCallback(callback);
    _dispatcher = null;
    if (_observingPop) {
      WidgetsBinding.instance.removeObserver(this);
      _observingPop = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
