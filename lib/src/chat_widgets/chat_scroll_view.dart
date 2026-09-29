import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_day_header_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_element.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_request.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Builds the widget for message [id].
///
/// [message] and [status] describe slot state for ids the viewport builds:
///
/// | [message] | [status] | Meaning | Recommended widget |
/// |-----------|----------|---------|--------------------|
/// | non-null  | any      | Message loaded | Render the bubble |
/// | null      | `dirty` / `fetching` | Fetch in flight | Shimmer / loading skeleton |
/// | null      | `valid`  | Unloaded slot in a valid chunk | Shimmer until fetch completes |
///
/// **`status.isAbsent` is unreachable** in normal operation — confirmed-absent
/// ids are excluded in the render object before this builder runs (zero layout
/// height, no selection wrapper). Do not rely on returning `SizedBox.shrink()`
/// as a substitute for absent handling.
///
/// **Lint**: [ChatMessageStatus] is an `extension type` over `int` — a raw
/// `int` coerces silently with no runtime error. Use named constants.
///
/// When [ChatScrollView.chunkErrorBuilder] is wired *and* the message's
/// chunk is in error state, this builder is **not** invoked for any id in
/// that chunk — the chunk renders as a single chunk-level tile instead.
/// Without that builder, ids in the errored chunk are passed to this builder
/// with `status.isError == true`.
///
/// [runLayout] is viewport-computed sender-run position from
/// [ChatScrollView.senderRunLayout] — participates in skip-rebuild cache
/// invalidation when neighbors change. Use for avatar/tail/padding; do not
/// walk neighbors ad hoc.
typedef ChatMessageBuilder =
    Widget Function(
      BuildContext context,
      int id,
      IChatMessage? message,
      ChatMessageStatus status,
      MessageRunLayout runLayout,
    );

/// Builds a group separator for the section starting at [firstMessageDate].
///
/// [bucket] is the raw key returned by [ChatScrollView.groupBy] for that
/// section — a `DateTime` truncated to the day with the default grouper, or
/// any equatable value for custom grouping (week label, `(year, month)`, …).
/// The same builder produces both the inline divider above the first message
/// of each group and the floating header pinned to the top of the viewport.
typedef ChatGroupSeparatorBuilder =
    Widget Function(
      BuildContext context,
      Object bucket,
      DateTime firstMessageDate,
    );

/// Information passed to a [ChatChunkErrorBuilder] when its chunk has failed
/// to load.
///
/// * [chunkIndex] — pagination index of the chunk (`ChatScrollChunk.chunkOf`);
///   useful for logging or chunk-scoped diagnostics.
/// * [firstId] / [lastId] — inclusive id range the chunk would cover when
///   fully loaded. The conversation's actual boundaries may sit inside this
///   range — clamp against `ChatDataSource.oldestKnownId` /
///   `newestKnownId` if your UI needs the visible portion.
/// * [error] — the last exception thrown by `fetchRange`. `null` only on
///   the first frame before any fetch resolved, which is unusual since the
///   builder is invoked once the chunk's status is `error`.
/// * [attempt] — count of failed fetch attempts since the last success (both
///   automatic-backoff and user-driven retries). Use it to render copy like
///   "Still failing (attempt 3)".
/// * [retry] — fire-and-forget callback that cancels any pending backoff and
///   re-fetches the chunk immediately.
typedef ChatChunkErrorDetails = ({
  int chunkIndex,
  int firstId,
  int lastId,
  Object? error,
  int attempt,
  VoidCallback retry,
});

/// Builds the error widget shown in place of an entire failed chunk.
///
/// One widget per chunk — not 64 per-message tiles — sits where the chunk
/// would have lived, sized to its own intrinsic height. See
/// [ChatChunkErrorDetails] for the data handed in and the retry hook.
typedef ChatChunkErrorBuilder =
    Widget Function(BuildContext context, ChatChunkErrorDetails details);

/// Default day grouping — the local calendar day. A `DateTime` with
/// hours/minutes/seconds zeroed is equatable enough for the day-bucket gate;
/// no need to pack y/m/d into an int.
DateTime _defaultGroupBy(IChatMessage message) {
  final d = message.createdAt.toLocal();
  return DateTime(d.year, d.month, d.day);
}

/// Widget-based endless chat viewport.
///
/// Anchor-based (id-relative) layout: messages are positioned around
/// [ChatScrollController.anchorMessageId], never against a global content
/// height. Children are real widgets — built lazily during layout via a
/// custom [ChatScrollElement] and wrapped in [RepaintBoundary] for picture +
/// layer caching. Scrolling repositions cached layers without re-layout.
///
/// When child Y offsets change (user / programmatic **reposition**, fan-out,
/// or **reserved inset** compensation), the element dispatches a synthetic
/// [ScrollUpdateNotification] after the frame so ancestor
/// [ScrollNotificationObserver] hosts can refresh absolute overlays. This is
/// not a [Scrollable]; notification metrics are not a chat scroll position.
///
/// Pass [dateSeparatorBuilder] to group messages by day — an inline separator
/// above the first message of each day plus a floating header pinned to the
/// top showing the topmost day.
///
/// Pass [unreadBoundary] and [unreadSeparatorBuilder] to mark where unread
/// content begins — an unread separator stacked as row chrome above the
/// boundary message.
class ChatScrollView extends RenderObjectWidget {
  /// Creates an anchor-based chat viewport backed by [dataSource] and
  /// [controller], building each visible row with [messageBuilder].
  const ChatScrollView({
    required this.dataSource,
    required this.controller,
    required this.messageBuilder,
    this.chunkErrorBuilder,
    this.emptyBuilder,
    this.loadingBuilder,
    this.selectionController,
    this.onIdleMessageTap,
    this.onSecondaryMessageTap,
    this.selectionChromeBuilder,
    this.bottomPadding,
    this.topPadding,
    this.dateSeparatorBuilder,
    this.groupBy,
    this.dayHeaderDelegate = const ChatFadingDayHeader(),
    this.unreadBoundary,
    this.unreadSeparatorBuilder,
    this.scrollActivityTiming,
    this.senderRunLayout = DefaultChatSenderRunLayout.instance,
    this.highlightColor,
    this.highlightDuration,
    this.textDirection,
    this.cacheExtent = 250.0,
    this.extraBuildExtent = 0.0,
    this.reverse = false,
    this.isSelfMessage,
    this.physics,
    this.scrollbar,
    super.key,
  });

  /// Owns message data, chunks, and the fetch contract.
  final ChatDataSource dataSource;

  /// Owns anchor state, conversation boundaries, and jumps.
  final ChatScrollController controller;

  /// Builds the widget for each message id. Pass a stable reference (a
  /// top-level function or a cached closure) — a new closure each parent
  /// rebuild forces every visible message to re-inflate.
  final ChatMessageBuilder messageBuilder;

  /// Builds the failure tile shown in place of an entire errored chunk.
  ///
  /// When set, an errored chunk in the build range is replaced by **one**
  /// widget (sized to its own intrinsic height) rather than per-message
  /// placeholders carrying `status.isError`. When this builder fires,
  /// [messageBuilder] is **not** called for any id in that chunk —
  /// chunk-level rendering fully replaces per-message rendering for the
  /// affected range. When `null`, falls back to the per-message path —
  /// [messageBuilder] receives the error status for every id and chooses
  /// what to render.
  ///
  /// The supplied [ChatChunkErrorDetails.retry] cancels the running backoff
  /// and re-fetches the chunk immediately. Pass a stable reference, like
  /// [messageBuilder].
  final ChatChunkErrorBuilder? chunkErrorBuilder;

  /// Builds the full-viewport widget shown when the conversation is known to
  /// be empty (data source reports [ChatDataSource.isEmpty]).
  ///
  /// When `null`, the viewport simply renders nothing — `messageBuilder`
  /// is never called because no ids exist.
  ///
  /// Like [loadingBuilder] and [chunkErrorBuilder], invoked during the
  /// viewport's layout pass — avoid triggering `setState` / `markNeedsLayout`
  /// synchronously from inside this builder.
  final WidgetBuilder? emptyBuilder;

  /// Builds the full-viewport skeleton shown before the first chunk lands
  /// (data source reports [ChatDataSource.isInitialLoading]).
  ///
  /// When `null`, the viewport falls back to the standard fan-out path: the
  /// `messageBuilder` is invoked with `message: null` and a fetching status
  /// for ids around the anchor, and whatever placeholder *your* builder
  /// produces in that case (shimmer, blank space, …) fills the viewport.
  /// The package itself does not ship a built-in placeholder.
  final WidgetBuilder? loadingBuilder;

  /// Optional selection facade. When non-null each **loaded** message
  /// whose [ChatSelectionAllowed.showsChrome] is true is wrapped in
  /// [SelectableMessage] for chrome. [ChatSelectionAllowed.none] rows
  /// are not wrapped. The viewport owns long-press and tap and drives
  /// **message selection**. **Text selection** subject/range/policy/Copy
  /// live on the same facade; the list is not wrapped in a markdown
  /// library selection scope. Placeholder / shimmer slots
  /// (`message == null`) are not wrapped and cannot be selected. When
  /// null the viewport adds no selection wrapper and costs nothing.
  final ChatSelectionController? selectionController;

  /// Called when the user taps a present message **slot** while message
  /// selection and text selection are both inactive. Null is a no-op.
  ///
  /// Receives a [ChatMessageMenuRequest] (id, slot, tap, point state,
  /// membership / over-selection, text-selection overlap, optional inline
  /// hit). Never fired when [selectionController] is in
  /// message selection mode or when text selection is active — message menu
  /// and selection modes are mutually exclusive on this path. When text
  /// selection is active, an idle tap dismisses text selection without
  /// dispatching here.
  ///
  /// The viewport-owned pointer attaches when this callback or
  /// [selectionController] is non-null. Not gated on selection-allowed.
  /// A tap that lost the arena, a fling-cancel tap, a gap, shimmer,
  /// chunk-error, or empty background does not fire. The pinned date
  /// header hits through to the message underneath, matching selection
  /// tap. Opening the menu from this request does not clear membership or
  /// text selection. The host decides whether to present a message menu.
  final ChatMessageMenuRequestCallback? onIdleMessageTap;

  /// Called when the user secondary-taps (right-clicks) a present message
  /// **slot**. Null is a no-op — Flutter’s built-in text context menu stays
  /// available on selectable markdown.
  ///
  /// Under desktop/web **selection policy** this is the message-menu entry
  /// gesture — including while message selection is active (**membership**
  /// upon-selected / elsewhere) and while text selection is live (overlap +
  /// snapshot on the request). The request also carries **point state** and
  /// an optional **inline hit**. When non-null on `$Desktop`, the viewport
  /// owns secondary on the **full slot** (including text glyphs); per-body
  /// markdown yields so Flutter’s text menu does not stack. Under `$Mobile`,
  /// secondary may still be wired, but adaptive **text selection chrome**
  /// stays — message-menu entry is idle primary tap. Opening the menu from
  /// this request does not clear membership or text selection.
  final ChatMessageMenuRequestCallback? onSecondaryMessageTap;

  /// Replaces the bundled checkbox-gutter chrome. Ignored when
  /// [selectionController] is null.
  ///
  /// The viewport owns the selection pointer and freeze-on-exit; this
  /// builder only paints. Use [ChatSelectionChromeState.selectProgress]
  /// (frozen on `clear`) rather than [ChatSelectionChromeState.isSelected]
  /// for visuals.
  /// Pass a stable tear-off, like [messageBuilder].
  ///
  /// Defaults to [DefaultSelectionChrome.wrap]. Restyle that chrome with
  /// [ChatSelectionThemeData] / [ChatScrollTheme]; replace layout here.
  final ChatSelectionChromeBuilder? selectionChromeBuilder;

  /// Empty space reserved inside the viewport after the newest message.
  ///
  /// Use it to keep the newest message clear of chrome stacked on top of the
  /// viewport — the composer, attachment previews, status strips. The viewport
  /// listens to it and relayouts when the value changes, so the inset can grow
  /// and shrink (e.g. a multi-line input field) without a jump.
  final ValueListenable<double>? bottomPadding;

  /// Empty space reserved at the top of the viewport — for chrome stacked over
  /// the viewport top (an app bar). The floating day header rests just below
  /// this inset.
  ///
  /// A change moves the scroll band's top edge without shifting on-screen
  /// messages (unlike [bottomPadding], it is not compensated) — except
  /// while a [ChatScrollController.jumpTo] alignment or
  /// [ChatScrollController.jumpToCenterBand] placement is held: the target
  /// row is then re-placed against the new edge, so top chrome that appears
  /// before the reader first scrolls does not cover it.
  final ValueListenable<double>? topPadding;

  /// When non-null, enables message grouping: an inline separator above the
  /// first message of each group plus a floating header for the topmost group.
  /// `null` disables the feature entirely.
  ///
  /// The builder receives the raw `groupBy` [bucket] and `firstMessageDate`
  /// (`createdAt` of the first message in that group). Format labels from
  /// `bucket` when it is not a `DateTime`, or from `firstMessageDate` for day
  /// grouping.
  ///
  /// How the inline separator and the floating header share the top of the
  /// viewport is the [dayHeaderDelegate]'s call.
  ///
  /// Pass a stable reference, like [messageBuilder].
  final ChatGroupSeparatorBuilder? dateSeparatorBuilder;

  /// Day header policy: where the floating header paints, at what opacity,
  /// and how inline separators behave near it. Consulted only when
  /// [dateSeparatorBuilder] is set.
  ///
  /// Default: [ChatFadingDayHeader] — the header stays at its rest line and
  /// inline separators fade out as they rise into it.
  /// [ChatPushingDayHeader] pushes the header up with the next day's
  /// separator instead. Implement [ChatDayHeaderDelegate] for any other
  /// policy. Prefer a const or value-equal instance across rebuilds.
  final ChatDayHeaderDelegate dayHeaderDelegate;

  /// Message id of the **unread boundary**: the row that carries the unread
  /// separator. `null` (or a `null` value) paints no separator.
  ///
  /// The host owns what the id means — which messages count as unread, when
  /// the boundary appears, and when it goes away. The viewport only paints
  /// [unreadSeparatorBuilder] above that id; it knows nothing about read
  /// state, message authors, or unread counts.
  ///
  /// The separator appears only on a **loaded** message row. A boundary whose
  /// row is still a placeholder (shimmer), sits in an errored chunk, or is
  /// absent paints nothing. The row gains the separator the next time it is
  /// built as a loaded message.
  ///
  /// The viewport listens while mounted. A value change — set, move, or
  /// clear — rebuilds only the old and the new boundary row; no other row
  /// rebuilds. The new row rebuilds at once, and the old row rebuilds when
  /// its separator has finished leaving. Replacing the listenable with a
  /// different instance acts as a change from the old value to the new one:
  /// the old instance is no longer heard, and nothing rebuilds when both
  /// hold the same id.
  ///
  /// The separator animates in and out with the list-item timings of the
  /// message change transition. Leaving, it fades out over 120 ms while
  /// its slot collapses over 250 ms. Arriving, its slot grows over 250 ms
  /// while it fades in and scales up from 0.9. A move runs both at once. A
  /// change during a transition reverses it from where it is, without a
  /// jump. A separator that is transitioning takes no input. Only a row
  /// laid out on the previous frame animates; any other row gains or loses
  /// the separator in one frame, as does every row while `TickerMode` is
  /// off.
  ///
  /// Adding or removing the separator changes the boundary row's height
  /// without moving what the reader sees, on every frame of the transition.
  /// The message row at the bottom of the scroll band keeps its screen
  /// position: a boundary row on screen or above it grows or shrinks
  /// upward, and one below the band grows off screen. At the tail the newest
  /// row stays pinned above the bottom inset. An in-flight navigation, a
  /// stitch, or a delete recovery keeps ownership of the scroll origin on
  /// its frames. When the changed row is the target of a held
  /// [ChatScrollController.jumpTo] alignment (or
  /// [ChatScrollController.jumpToCenterBand] placement), the placement is
  /// re-applied instead, on every frame: after `jumpTo(boundary,
  /// alignment: 0)` the added separator grows from the band top with the
  /// body below it.
  ///
  /// A change made by a tail-or-target listener
  /// ([ChatScrollController.addTailOrTargetListener]) lands without a
  /// transition, in the same layout.
  final ValueListenable<int?>? unreadBoundary;

  /// Builds the **unread separator** shown above the [unreadBoundary] row.
  /// Ignored when [unreadBoundary] is `null`.
  ///
  /// The separator is row chrome: it gets the full row width, picks its own
  /// height, and stacks below the inline date separator (when the boundary
  /// row starts a day) and above the message body. It works with or without
  /// [dateSeparatorBuilder].
  ///
  /// Unlike the inline date separator, the [dayHeaderDelegate] never fades
  /// or hides it: at rest it is painted opaque, and only its enter and exit
  /// transition (see [unreadBoundary]) changes its opacity, scale, and
  /// slot height. It is composed outside selection chrome and outside the
  /// secondary-tap scope, and a press on it is row chrome: it never starts
  /// message selection and never produces a message menu request. Gestures inside the built widget still work.
  ///
  /// The builder receives only a build context — text, localization, and
  /// styling are host chrome. Pass a stable reference, like
  /// [messageBuilder]: a new instance rebuilds every built row.
  final WidgetBuilder? unreadSeparatorBuilder;

  /// Timing of the viewport's scroll-activity clock, or `null` (the default)
  /// to run none — activity then stays at `1`.
  ///
  /// Scroll activity rises when the list moves and falls once scrolling has
  /// been idle; see [ChatScrollActivityTiming]. The viewport publishes it to
  /// [dayHeaderDelegate] and to every row chrome delegate, so chrome such as
  /// the floating header can hide while the list rests.
  ///
  /// Hiding takes both knobs: this clock supplies activity, and each delegate
  /// decides whether to follow it (the built-in day header policies do by
  /// default — see their `hidesWhenIdle`).
  final ChatScrollActivityTiming? scrollActivityTiming;

  /// Groups messages into sections — messages whose returned keys are equal
  /// (`==`) share a section. Consulted only when [dateSeparatorBuilder] is
  /// set; defaults to the local calendar day.
  ///
  /// The separator builder receives [bucket] directly, so non-`DateTime` keys
  /// (weekly / monthly labels, custom records) work without being coerced to
  /// a date. Pass a stable reference.
  final Object Function(IChatMessage message)? groupBy;

  /// Policy that resolves [MessageRunLayout] for each built message.
  ///
  /// Default: [DefaultChatSenderRunLayout.instance] (same sender, optional
  /// [groupBy] bucket, 5-minute `|createdAt|` window). Replace with a custom
  /// [ChatSenderRunLayout] or `DefaultChatSenderRunLayout(maxClusterGap: …)`
  /// to change clustering without forking the package. Prefer a stable /
  /// value-equal instance across rebuilds.
  ///
  /// Host chrome via [MessageRunLayout.extras]:
  ///
  /// - Rare: pass a new unequal policy instance (widget rebuild).
  /// - Live: keep one instance that implements [Listenable] and notify when
  ///   extras inputs change. The render object listens; do not call
  ///   [ChatDataSource.notifyDataChanged] for chrome-only updates.
  final ChatSenderRunLayout senderRunLayout;

  /// Peak colour of the navigate-select **underlay**.
  ///
  /// Alpha drives wash strength; text/bubbles paint above it. Set alpha to 0
  /// to opt out without changing [highlightDuration].
  ///
  /// Null → [ChatScrollThemeData.highlightColor] (package default if unset).
  final Color? highlightColor;

  /// Solid hold after settle for navigate-select highlight.
  ///
  /// Fade after hold is fixed (~300ms). [Duration.zero] disables the feature —
  /// `animateTo` lands without tint.
  ///
  /// Null → [ChatScrollThemeData.highlightDuration].
  final Duration? highlightDuration;

  /// Reading direction. `null` (the default) inherits from `Directionality`
  /// of the build context — set explicitly to override (e.g. force LTR for
  /// a specific chat thread inside an RTL app).
  ///
  /// Drives where the scrollbar paints (right in LTR, left in RTL) and where
  /// its mouse strip and touch target live. The `messageBuilder` does not
  /// receive this value
  /// — to mirror bubble alignment, read `Directionality.of(context)` inside
  /// the builder.
  final TextDirection? textDirection;

  /// Pixels above and below the viewport to keep built.
  final double cacheExtent;

  /// Extra pixels beyond [cacheExtent] that stay built while off-screen
  /// (paint-culled), so a message's `State` survives a short scroll out and
  /// back. `0` (the default) collects children as soon as they leave the
  /// cache extent.
  ///
  /// Distance-based only — unrelated to the `KeepAlive` widget, which retains
  /// specific children regardless of how far they scroll away.
  final double extraBuildExtent;

  /// When the entire conversation fits in the viewport, where should the
  /// content stack?
  ///
  /// * `false` (list-style, default): pin the oldest message to the top, gap
  ///   below the newest. Matches `ListView`-shaped UIs.
  /// * `true` (chat-style): pin the newest message to the bottom, gap above
  ///   the oldest. Typical for short conversations that still feel like a chat.
  ///
  /// Also flips the assistive-tech mapping for `scrollUp`/`scrollDown`
  /// actions: in `reverse` mode `scrollUp` reveals older history (what
  /// chat-app users expect).
  final bool reverse;

  /// Host-relative predicate: messages authored by the signed-in user.
  ///
  /// When non-null, an [InsertMutation] / [InsertBatchMutation] that includes
  /// any matching message forces follow-tail (`animateTo` newest) even if the
  /// viewport was scrolled into history. Incoming-only inserts still follow
  /// only when already at the tail.
  ///
  /// Do **not** put "outgoing" on [IChatMessage]: that is session-relative.
  /// Pass the same predicate to unread chrome so self inserts do not inflate
  /// the page-down badge.
  final bool Function(IChatMessage message)? isSelfMessage;

  /// Scroll physics: the fling that carries a released drag and the edge
  /// effect shown at a reached conversation boundary.
  ///
  /// `null` resolves to [ChatScrollPhysics.forPlatform] on every build: the
  /// preset matching the OS family of [defaultTargetPlatform] (not the
  /// theme's platform); a browser follows its OS.
  ///
  /// Physics governs the user drag path only (touch, stylus, trackpad pan,
  /// and the flings they release). Wheel, keyboard, scrollbar, jump, and
  /// animate motion never read it.
  ///
  /// Compared by value on rebuild: an equal value is a no-op, so an
  /// in-flight fling or edge effect survives. An unequal value cancels the
  /// in-flight fling (emitting [ChatFlingEnd]) and drops the edge effect to
  /// rest before the new physics takes over.
  final ChatScrollPhysics? physics;

  /// The **scrollbar preset**: a scrollbar drawn by a
  /// [ChatScrollbarPainter], shown per a [ChatScrollbarVisibility], and
  /// grabbed per a [ChatScrollbarGrab], or [ChatScrollbar.none] for no
  /// scrollbar.
  ///
  /// `null` resolves to `const ChatScrollbar()` on every build: the
  /// [ChatPillScrollbarPainter] at its defaults, always shown, with the
  /// default grab rules. Colours come from [ChatScrollbarThemeData]; the
  /// painter picks sizes; where the scrollbar sits follows [textDirection].
  ///
  /// Compared by value on rebuild: an equal value is a no-op, so a grab in
  /// progress and a pending auto-hide survive. An unequal value ends the
  /// grab — the grabbing pointer then scrolls nothing until it lifts — and
  /// the new visibility takes over from the value currently shown.
  final ChatScrollbar? scrollbar;

  /// The effective physics: [physics], or the platform default when unset.
  ChatScrollPhysics get _effectivePhysics =>
      physics ?? ChatScrollPhysics.forPlatform();

  /// The effective scrollbar: [scrollbar], or the default preset when unset.
  ChatScrollbar get _effectiveScrollbar => scrollbar ?? const ChatScrollbar();

  /// The effective grouping function, or `null` when day separators are off.
  Object Function(IChatMessage)? get _effectiveGroupBy =>
      dateSeparatorBuilder == null ? null : (groupBy ?? _defaultGroupBy);

  @override
  RenderObjectElement createElement() => ChatScrollElement(this);

  /// Effective reading direction: an explicit override wins; otherwise read
  /// from `Directionality`, falling back to `TextDirection.ltr` only when
  /// no `Directionality` ancestor is in scope.
  TextDirection _resolveDirection(BuildContext context) =>
      textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;

  @override
  RenderChatScrollView createRenderObject(BuildContext context) {
    final theme = ChatScrollTheme.resolve(context);
    return RenderChatScrollView(
      dataSource: dataSource,
      controller: controller,
      cacheExtent: cacheExtent,
      extraBuildExtent: extraBuildExtent,
      ticking: TickerMode.valuesOf(context).enabled,
      reverse: reverse,
      bottomPadding: bottomPadding,
      topPadding: topPadding,
      groupBy: _effectiveGroupBy,
      dayHeaderDelegate: dayHeaderDelegate,
      scrollActivityTiming: scrollActivityTiming,
      senderRunLayout: senderRunLayout,
      unreadBoundary: unreadBoundary,
      hasErrorBuilder: chunkErrorBuilder != null,
      hasEmptyBuilder: emptyBuilder != null,
      hasLoadingBuilder: loadingBuilder != null,
      highlightColor: highlightColor ?? theme.highlightColor!,
      highlightDuration: highlightDuration ?? theme.highlightDuration!,
      textDirection: _resolveDirection(context),
      scrollbarTheme: theme.scrollbar!,
      scrollbar: _effectiveScrollbar,
      selectionController: selectionController,
      onIdleMessageTap: onIdleMessageTap,
      onSecondaryMessageTap: onSecondaryMessageTap,
      isSelfMessage: isSelfMessage,
      physics: _effectivePhysics,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    final theme = ChatScrollTheme.resolve(context);
    renderObject
      ..dataSource = dataSource
      ..controller = controller
      ..cacheExtent = cacheExtent
      ..extraBuildExtent = extraBuildExtent
      ..ticking = TickerMode.valuesOf(context).enabled
      ..reverse = reverse
      ..bottomPadding = bottomPadding
      ..topPadding = topPadding
      ..groupBy = _effectiveGroupBy
      ..dayHeaderDelegate = dayHeaderDelegate
      ..scrollActivityTiming = scrollActivityTiming
      ..senderRunLayout = senderRunLayout
      ..unreadBoundary = unreadBoundary
      ..hasErrorBuilder = chunkErrorBuilder != null
      ..hasEmptyBuilder = emptyBuilder != null
      ..hasLoadingBuilder = loadingBuilder != null
      ..highlightColor = highlightColor ?? theme.highlightColor!
      ..highlightDuration = highlightDuration ?? theme.highlightDuration!
      ..scrollbarTheme = theme.scrollbar!
      ..scrollbar = _effectiveScrollbar
      ..textDirection = _resolveDirection(context)
      ..selectionController = selectionController
      ..onIdleMessageTap = onIdleMessageTap
      ..onSecondaryMessageTap = onSecondaryMessageTap
      ..isSelfMessage = isSelfMessage
      ..physics = _effectivePhysics;
  }
}
