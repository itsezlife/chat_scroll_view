import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_delegate.dart';
import 'package:flutter/foundation.dart';

/// Inputs a [ChatDayHeaderDelegate] resolves the floating day header
/// against, in viewport-local pixels.
@immutable
final class ChatDayHeaderMetrics {
  /// Metrics for a header resting at [restTop], [extent] tall.
  const ChatDayHeaderMetrics({
    required this.restTop,
    required this.extent,
    this.leadingSeparatorTop,
    this.activity = 1.0,
  });

  /// Y where the header rests — just below the viewport's top inset, or
  /// lower when a top edge effect paints the oldest row below that inset:
  /// the header never rests above the oldest row.
  final double restTop;

  /// Laid-out header height.
  final double extent;

  /// Paint Y of the topmost inline day separator that is not yet fully
  /// above the rest line — the smallest separator top greater than
  /// `restTop - extent`. Separators are assumed to be [extent] tall, since
  /// the header and the inline separator come from the same builder. `null`
  /// when no such separator is built.
  final double? leadingSeparatorTop;

  /// Scroll activity in `[0, 1]` — see [ChatRowChromeMetrics.activity].
  final double activity;
}

/// Where the floating day header paints and whether it takes input.
@immutable
final class ChatFloatingHeaderEffect {
  /// A header displaced by [offset] from its rest line and painted at
  /// [opacity]. [hitTestable] defaults to `opacity > 0`.
  const ChatFloatingHeaderEffect({
    this.offset = 0.0,
    this.opacity = 1.0,
    this.holdsActivity = false,
    bool? hitTestable,
  }) : hitTestable = hitTestable ?? opacity > 0.0;

  /// Displacement from the rest line; negative pushes the header up.
  final double offset;

  /// Paint opacity in `[0, 1]`.
  final double opacity;

  /// Whether the viewport holds scroll activity at `1` this frame: the header
  /// stands in for an inline separator hidden under it and must stay fully
  /// shown. Once cleared, activity idles out from `1` — so a scroll that
  /// starts from here never finds the header hidden.
  final bool holdsActivity;

  /// Whether the header takes pointer input. A header that does not take
  /// input also stops covering the row chrome beneath it for message
  /// selection.
  final bool hitTestable;

  @override
  bool operator ==(Object other) =>
      other is ChatFloatingHeaderEffect &&
      other.offset == offset &&
      other.opacity == opacity &&
      other.holdsActivity == holdsActivity &&
      other.hitTestable == hitTestable;

  @override
  int get hashCode => Object.hash(offset, opacity, holdsActivity, hitTestable);

  @override
  String toString() =>
      'ChatFloatingHeaderEffect(offset: $offset, opacity: $opacity, '
      'holdsActivity: $holdsActivity, hitTestable: $hitTestable)';
}

/// Day header policy: how the floating header and the inline day separators
/// share the top of the viewport.
///
/// The viewport calls [resolveFloatingHeader] every scroll frame and every
/// scroll-activity change; it must be pure and cheap. [inlineSeparator] is
/// the row chrome delegate the viewport gives every inline day separator,
/// so the two halves of one policy always agree.
///
/// Built-in policies: [ChatFadingDayHeader] (the default) and
/// [ChatPushingDayHeader]. Replacing the policy with one that is not `==`
/// relayouts the viewport and rebuilds its rows.
abstract interface class ChatDayHeaderDelegate {
  /// Const constructor for the built-in policies.
  const ChatDayHeaderDelegate();

  /// The floating header's effect for this frame.
  ChatFloatingHeaderEffect resolveFloatingHeader(ChatDayHeaderMetrics metrics);

  /// Row chrome delegate for inline day separators.
  ChatRowChromeDelegate get inlineSeparator;
}

/// The header stays at its rest line; inline separators fade out over
/// [fadeBand] pixels as they rise into it.
///
/// With [hidesWhenIdle], the header follows scroll activity, except while an
/// inline separator overlaps its zone and is faded under it.
@immutable
final class ChatFadingDayHeader extends ChatDayHeaderDelegate {
  /// Fading policy.
  const ChatFadingDayHeader({this.fadeBand = 20, this.hidesWhenIdle = true})
    : assert(fadeBand > 0, 'fadeBand must be positive');

  /// Travel over which an inline separator fades under the header.
  final double fadeBand;

  /// Whether the header hides once scrolling goes idle. Has no effect unless
  /// the viewport runs a scroll-activity clock.
  final bool hidesWhenIdle;

  @override
  ChatFloatingHeaderEffect resolveFloatingHeader(ChatDayHeaderMetrics metrics) {
    final lead = metrics.leadingSeparatorTop;
    final held =
        hidesWhenIdle &&
        lead != null &&
        lead < metrics.restTop + metrics.extent;
    return ChatFloatingHeaderEffect(
      opacity: hidesWhenIdle && !held ? metrics.activity : 1.0,
      holdsActivity: held,
    );
  }

  @override
  ChatRowChromeDelegate get inlineSeparator =>
      ChatRowChromeDelegate.fadeUnderHeader(band: fadeBand);

  @override
  bool operator ==(Object other) =>
      other is ChatFadingDayHeader &&
      other.fadeBand == fadeBand &&
      other.hidesWhenIdle == hidesWhenIdle;

  @override
  int get hashCode => Object.hash(ChatFadingDayHeader, fadeBand, hidesWhenIdle);
}

/// The next day's inline separator pushes the header up as it rises into
/// it; once the separator reaches the rest line, the header takes its place
/// and the inline separator hides.
///
/// Push: while the leading separator's top is within one header extent below
/// the rest line, the header is displaced by
/// `leadingSeparatorTop - restTop - extent`, so the separator's top edge
/// touches the header's bottom edge. The oldest row rests at the rest line,
/// so the separator doing the pushing always opens a later day than the
/// header shows.
///
/// With [hidesWhenIdle], the header follows scroll activity, except while it
/// stands in for an inline separator hidden under it.
@immutable
final class ChatPushingDayHeader extends ChatDayHeaderDelegate {
  /// Pushing policy.
  const ChatPushingDayHeader({this.hidesWhenIdle = true});

  /// Whether the header hides once scrolling goes idle. Has no effect unless
  /// the viewport runs a scroll-activity clock.
  final bool hidesWhenIdle;

  @override
  ChatFloatingHeaderEffect resolveFloatingHeader(ChatDayHeaderMetrics metrics) {
    final lead = metrics.leadingSeparatorTop;
    if (lead == null) {
      return ChatFloatingHeaderEffect(
        opacity: hidesWhenIdle ? metrics.activity : 1.0,
      );
    }
    if (lead <= metrics.restTop) {
      return ChatFloatingHeaderEffect(holdsActivity: hidesWhenIdle);
    }
    final pushed = lead < metrics.restTop + metrics.extent;
    return ChatFloatingHeaderEffect(
      offset: pushed ? lead - metrics.restTop - metrics.extent : 0.0,
      opacity: hidesWhenIdle ? metrics.activity : 1.0,
    );
  }

  @override
  ChatRowChromeDelegate get inlineSeparator =>
      const ChatRowChromeDelegate.hideUnderHeader();

  @override
  bool operator ==(Object other) =>
      other is ChatPushingDayHeader && other.hidesWhenIdle == hidesWhenIdle;

  @override
  int get hashCode => Object.hash(ChatPushingDayHeader, hidesWhenIdle);
}
