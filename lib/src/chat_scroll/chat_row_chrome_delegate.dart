import 'package:flutter/foundation.dart';

/// Where the floating day header sits this frame, in viewport-local pixels.
///
/// The viewport resolves the zone once per frame from its
/// `ChatDayHeaderDelegate` and hands the same value to every row chrome
/// delegate, so row chrome can react to the header without knowing which
/// header policy is active.
@immutable
final class ChatFloatingHeaderZone {
  /// A header resting at [restTop], [extent] tall, displaced by [offset] and
  /// painted at [opacity].
  const ChatFloatingHeaderZone({
    required this.restTop,
    required this.extent,
    this.offset = 0.0,
    this.opacity = 1.0,
  });

  /// No floating header: grouping is off, the header is suppressed, or the
  /// row is not a viewport child.
  static const ChatFloatingHeaderZone none = ChatFloatingHeaderZone(
    restTop: 0,
    extent: 0,
    opacity: 0,
  );

  /// Y where the header rests when nothing displaces it — just below the
  /// viewport's top inset.
  final double restTop;

  /// Laid-out header height; `0` when there is no header.
  final double extent;

  /// Displacement from [restTop] chosen by the header policy; negative when
  /// the header is pushed up.
  final double offset;

  /// Header paint opacity in `[0, 1]`.
  final double opacity;

  /// Whether a header occupies the zone at all.
  bool get isPresent => extent > 0;

  /// Painted top edge: [restTop] plus [offset].
  double get top => restTop + offset;

  /// Painted bottom edge.
  double get bottom => top + extent;

  @override
  bool operator ==(Object other) =>
      other is ChatFloatingHeaderZone &&
      other.restTop == restTop &&
      other.extent == extent &&
      other.offset == offset &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(restTop, extent, offset, opacity);

  @override
  String toString() =>
      'ChatFloatingHeaderZone(restTop: $restTop, extent: $extent, '
      'offset: $offset, opacity: $opacity)';
}

/// Inputs a [ChatRowChromeDelegate] resolves one chrome item against.
@immutable
final class ChatRowChromeMetrics {
  /// Metrics for one chrome item painted at [top], [extent] tall.
  const ChatRowChromeMetrics({
    required this.top,
    required this.extent,
    this.header = ChatFloatingHeaderZone.none,
    this.activity = 1.0,
  });

  /// Viewport-local paint Y of the item's top edge. Outside a viewport it is
  /// the item's offset within its row.
  final double top;

  /// The item's laid-out height.
  final double extent;

  /// The floating header zone this frame.
  final ChatFloatingHeaderZone header;

  /// Scroll activity in `[0, 1]`: `1` while the list moves and shortly
  /// after, easing to `0` once scrolling has been idle. Constant `1` when the
  /// viewport runs no activity clock.
  final double activity;

  /// Item bottom edge.
  double get bottom => top + extent;
}

/// How a chrome item paints and whether it takes input.
@immutable
final class ChatRowChromeEffect {
  /// An effect painted at [opacity]. [hitTestable] defaults to
  /// `opacity > 0`.
  const ChatRowChromeEffect({this.opacity = 1.0, bool? hitTestable})
    : hitTestable = hitTestable ?? opacity > 0.0;

  /// Fully painted and hit-testable.
  static const ChatRowChromeEffect visible = ChatRowChromeEffect();

  /// Not painted and not hit-testable. Layout space is kept.
  static const ChatRowChromeEffect hidden = ChatRowChromeEffect(opacity: 0);

  /// Paint opacity in `[0, 1]`. The row snaps values `>= 0.999` to opaque and
  /// skips painting at `<= 0.001`.
  final double opacity;

  /// Whether the item takes pointer input.
  final bool hitTestable;

  @override
  bool operator ==(Object other) =>
      other is ChatRowChromeEffect &&
      other.opacity == opacity &&
      other.hitTestable == hitTestable;

  @override
  int get hashCode => Object.hash(opacity, hitTestable);

  @override
  String toString() =>
      'ChatRowChromeEffect(opacity: $opacity, hitTestable: $hitTestable)';
}

/// Decides how one row chrome item presents itself for a frame.
///
/// The row calls [resolve] on every paint and hit test, so implementations
/// must be pure and cheap: no allocation beyond the returned effect, no side
/// effects. The row repaints when a delegate is replaced by one that is not
/// `==` to it, so value-equal delegates should implement `==`.
///
/// Built-in delegates: [ChatRowChromeDelegate.opaque],
/// [ChatRowChromeDelegate.fadeUnderHeader],
/// [ChatRowChromeDelegate.hideUnderHeader].
abstract interface class ChatRowChromeDelegate {
  /// Const constructor for the built-in delegates.
  const ChatRowChromeDelegate();

  /// Always painted and hit-testable.
  const factory ChatRowChromeDelegate.opaque() = ChatOpaqueRowChrome;

  /// Fades out over [band] pixels as the item rises into the floating
  /// header's painted bottom edge.
  const factory ChatRowChromeDelegate.fadeUnderHeader({double band}) =
      ChatFadeUnderHeaderRowChrome;

  /// Hidden while the floating header rests over the item — the header
  /// stands in for it.
  const factory ChatRowChromeDelegate.hideUnderHeader() =
      ChatHideUnderHeaderRowChrome;

  /// The effect for an item described by [metrics].
  ChatRowChromeEffect resolve(ChatRowChromeMetrics metrics);
}

/// [ChatRowChromeDelegate.opaque].
@immutable
final class ChatOpaqueRowChrome extends ChatRowChromeDelegate {
  /// Always visible.
  const ChatOpaqueRowChrome();

  @override
  ChatRowChromeEffect resolve(ChatRowChromeMetrics metrics) =>
      ChatRowChromeEffect.visible;

  @override
  bool operator ==(Object other) => other is ChatOpaqueRowChrome;

  @override
  int get hashCode => (ChatOpaqueRowChrome).hashCode;
}

/// [ChatRowChromeDelegate.fadeUnderHeader].
///
/// Opacity is `1` once the item's top clears the header's painted bottom and
/// falls linearly to `0` over [band] pixels above it, so the item and the
/// header never both show at full strength. With no header present the item
/// stays visible.
@immutable
final class ChatFadeUnderHeaderRowChrome extends ChatRowChromeDelegate {
  /// Fades over [band] pixels.
  const ChatFadeUnderHeaderRowChrome({this.band = 20})
    : assert(band > 0, 'band must be positive');

  /// Travel over which the item fades.
  final double band;

  @override
  ChatRowChromeEffect resolve(ChatRowChromeMetrics metrics) {
    final header = metrics.header;
    if (!header.isPresent) return ChatRowChromeEffect.visible;
    final opacity = ((metrics.top - header.bottom) / band + 1.0).clamp(
      0.0,
      1.0,
    );
    return ChatRowChromeEffect(opacity: opacity);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatFadeUnderHeaderRowChrome && other.band == band;

  @override
  int get hashCode => Object.hash(ChatFadeUnderHeaderRowChrome, band);
}

/// [ChatRowChromeDelegate.hideUnderHeader].
///
/// Hidden once the item's top reaches the header's rest line; visible below
/// it. The header's own push offset does not matter: at the rest line the
/// header takes over the item's content.
@immutable
final class ChatHideUnderHeaderRowChrome extends ChatRowChromeDelegate {
  /// Hides under the resting header.
  const ChatHideUnderHeaderRowChrome();

  @override
  ChatRowChromeEffect resolve(ChatRowChromeMetrics metrics) {
    final header = metrics.header;
    if (header.isPresent && metrics.top <= header.restTop) {
      return ChatRowChromeEffect.hidden;
    }
    return ChatRowChromeEffect.visible;
  }

  @override
  bool operator ==(Object other) => other is ChatHideUnderHeaderRowChrome;

  @override
  int get hashCode => (ChatHideUnderHeaderRowChrome).hashCode;
}
