import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart' show Listenable;

/// Where the app is in its lifecycle, the only platform input of a
/// `PlaybackActivity`.
///
/// A seam so the pause policy is driven by hand in tests; the production
/// adapter is `WidgetsPlaybackLifecycleSource`. Everything runs on the UI
/// isolate.
///
/// ## What the states mean on desktop
///
/// `resumed` is "visible and focused", `inactive` "visible but not focused"
/// (another app took the focus), `hidden` "minimised or not on any visible
/// desktop", and `paused` / `detached` are mobile and web states. The platform
/// reports `inactive` before `hidden`, so `resumed -> hidden` arrives as two
/// changes. On the web `inactive` is a blurred tab.
///
/// ## Contract
///
/// - [state] is what the platform said last, or `null` while it has not said
///   anything. A `null` is "unknown", never a reason to pause.
/// - Every change of [state] notifies the listeners once, with [state] already
///   the new value; setting the state it already has notifies nothing.
/// - After the source is disposed nothing is notified and the platform is no
///   longer observed.
abstract interface class PlaybackLifecycleSource implements Listenable {
  /// The last state reported, or `null` before any.
  AppLifecycleState? get state;
}
