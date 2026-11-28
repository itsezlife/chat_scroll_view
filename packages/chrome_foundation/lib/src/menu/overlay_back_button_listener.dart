import 'package:flutter/widgets.dart';

/// System-back handler for content shown in a root [Overlay].
///
/// Used instead of [BackButtonListener] because the selection menu is built in
/// an overlay entry that is not under a [Router], and [BackButtonListener]
/// calls `Router.of` on its own context and throws there.
///
/// Capture [parentDispatcher] from a context that is under the [Router] (the
/// field's) before the entry is built. When it is null (a [MaterialApp]
/// without a [Router]), the listener falls back to
/// [WidgetsBindingObserver.didPopRoute] while it is mounted.
class OverlayBackButtonListener extends StatefulWidget {
  /// Registers [onBackButtonPressed] with a child of [parentDispatcher].
  const OverlayBackButtonListener({
    required this.onBackButtonPressed,
    required this.child,
    this.parentDispatcher,
    super.key,
  });

  /// The root dispatcher from `Router.backButtonDispatcher`, or null to use the
  /// observer fallback.
  final BackButtonDispatcher? parentDispatcher;

  /// Called when the system back button is pressed; completes with true when
  /// it handled the event (the menu closed, and the route and keyboard stay).
  final ValueGetter<Future<bool>> onBackButtonPressed;

  /// The widget below this one.
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
  void didUpdateWidget(OverlayBackButtonListener oldWidget) {
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
