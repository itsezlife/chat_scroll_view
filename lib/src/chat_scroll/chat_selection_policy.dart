import 'package:flutter/foundation.dart';

/// **Selection policy** for how **message selection** and **text selection**
/// enter, nest or exclude each other, dismiss, and behave on Copy.
///
/// Hosts MUST NOT replace the policy on a live selection facade —
/// construct a new facade when the matrix must change.
sealed class ChatSelectionPolicy {
  /// Base constructor for policy variants.
  const ChatSelectionPolicy();

  /// Nested text subject; Copy clears message mode.
  const factory ChatSelectionPolicy.mobile() = ChatSelectionPolicy$Mobile;

  /// Exclusive modes; Copy keeps the character range.
  const factory ChatSelectionPolicy.desktop() = ChatSelectionPolicy$Desktop;

  /// Default from OS family. Pass [platform] / [isWeb] to pin in tests.
  factory ChatSelectionPolicy.forPlatform({
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (isWeb ?? kIsWeb) {
      return const ChatSelectionPolicy.desktop();
    }
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.android => const ChatSelectionPolicy.mobile(),
      _ => const ChatSelectionPolicy.desktop(),
    };
  }

  /// Whether text entry may proceed when [messageId] is not message-selected.
  bool get allowsTextEntryWithoutMessageSelection;

  /// Whether long-press routes into text selection for an already-selected
  /// message body.
  ///
  /// `true` under [$Mobile] (message-then-text: long-press on an already-selected
  /// message enters text selection).
  /// `false` under [$Desktop] (direct text entry via drag; long-press does not route).
  bool get routesLongPressToTextSelection;

  /// Whether the **text selection subject** must remain in the selected set
  /// while text is active.
  bool get nestsTextSubjectInMessageSelection;

  /// Whether primary tap (left-click / touch) on an idle message slot routes
  /// to `onIdleMessageTap`.
  ///
  /// On mobile (`$Mobile`), primary tap on an idle message opens message chrome
  /// (e.g. bottom sheet / message menu).
  /// On desktop (`$Desktop`), primary tap on an idle message does not open the
  /// message menu (which is secondary click / right-click), but instead focuses,
  /// clears active selection, or positions the caret.
  bool get routesPrimaryTapToIdleMessage;

  /// Whether long-press gestures rely on a timer duration rather than
  /// distance-based drag thresholds.
  ///
  /// On mobile, long-press uses a 500ms hold timer.
  /// On desktop, there is no timer-based long-press; gestures are drag-distance
  /// driven.
  bool get usesTimerBasedLongPress;

  /// Whether message selection shifts message bodies horizontally to open a
  /// start-side gutter for the selection check control.
  ///
  /// `true` under [$Mobile] (Behavior: bubbles slide horizontally
  /// to reveal the start-side checkbox).
  /// `false` under [$Desktop] (Behavior: bubbles remain stationary and the
  /// checkbox appears on the trailing edge).
  bool get shiftsBubbleForSelectionGutter;

  /// Whether the selection check control is positioned at the trailing edge of
  /// the message row.
  ///
  /// `false` under [$Mobile] (check slides into the start-side gutter).
  /// `true` under [$Desktop] (check is anchored to the trailing edge).
  bool get positionsSelectionCheckAtTrailingEdge;

  /// Whether message selection applies [ChatMessageChangeTransition.selectedColor]
  /// to the message bubble container.
  ///
  /// `false` under [$Mobile] (message selection is expressed via the start-side
  /// checkbox gutter and whole-row background tint, keeping the bubble container
  /// in its normal color).
  /// `true` under [$Desktop] (message selection recolors the message bubble container
  /// to [ChatMessageChangeTransition.selectedColor]).
  bool get appliesSelectedColorToBubble;

  /// Whether **message selection** mode suppresses ordinary inline
  /// activations (link opens, inline-code copy, fenced COPY chrome).
  ///
  /// Under [$Mobile] (`true`), tapping a row during message multiselect
  /// toggles message membership rather than navigating or copying
  /// (multiselect row tap takes precedence over inline activation).
  /// Under [$Desktop] (`false`), links and code are not suppressed by
  /// message membership alone.
  ///
  /// Independently, a live **character-range text selection** (non-collapsed)
  /// always suppresses inline activation on the facade under both policies.
  /// Mere arm-for-entry (desktop pointer-down) does not.
  bool get suppressesLinkTapInMessageSelection;

  /// Whether a wired [ChatScrollView.onSecondaryMessageTap] claims the full
  /// message **slot** for secondary (including glyphs), so per-body Flutter
  /// **text selection chrome** / context menus must yield.
  ///
  /// Under [$Desktop] (`true`), secondary is the **message menu** entry —
  /// text-range actions belong on that menu, not a second popup.
  /// Under [$Mobile] (`false`), the message menu is idle primary tap; the
  /// adaptive text toolbar stays even when secondary is also wired.
  bool get secondaryMessageTapOwnsFullSlot;

  /// Whether **tap highlight** (link / inline-code press ink) is suppressed
  /// while **message selection** mode or **text selection** is active.
  ///
  /// Under [$Mobile] (`true`), press ink does not arm during multiselect or
  /// while a character-range subject is active — selection chrome owns the
  /// interaction surface.
  /// Under [$Desktop] (`false`), press ink may arm regardless of selection
  /// state (desktop keep current link/code feedback).
  bool get suppressesTapHighlightDuringSelection;

  /// Character count threshold for showing the bottom "COPY CODE" bar on
  /// mobile platforms when [hasBottomCodeCopyBar] is true.
  static const int mobileCodeCopyBarThreshold = 75;

  /// Whether fenced code blocks have an interactive (clickable) top header.
  ///
  /// `true` under [$Desktop] (top header contains language label and clickable
  /// copy action).
  /// `false` under [$Mobile] (top header is informative only and non-clickable).
  bool get hasInteractiveCodeHeader;

  /// Whether fenced code blocks with >= [mobileCodeCopyBarThreshold] characters
  /// display an interactive bottom "COPY CODE" strip.
  ///
  /// `true` under [$Mobile].
  /// `false` under [$Desktop].
  bool get hasBottomCodeCopyBar;

  /// Whether an interactive bottom copy bar should be rendered for a code
  /// snippet with the given character [length].
  bool hasBottomCodeCopyBarForLength(int length);

  /// Membership side effects when entering text for [messageId].
  void applyEnterMembership({
    required void Function(Set<int> ids) replaceSelectedIds,
    required VoidCallback clearMessageSelection,
    required int messageId,
  });

  /// Post-clipboard Copy-success side effects.
  ///
  /// [clearTextSelection] / [clearMessageSelection] are supplied by the
  /// facade so this type does not own clipboard I/O.
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  });
}

/// Mobile **selection policy**.
///
/// Message-then-text: first long-press enters **message selection**; a
/// further long-press on an already-selected subject body enters **text
/// selection**. Enter preserves existing **message selection** membership.
/// Dismiss-text keeps all selected messages. Copy success clears
/// text and message mode.
final class ChatSelectionPolicy$Mobile implements ChatSelectionPolicy {
  /// Creates the mobile policy variant.
  const ChatSelectionPolicy$Mobile();

  @override
  bool get allowsTextEntryWithoutMessageSelection => false;

  @override
  bool get routesLongPressToTextSelection => true;

  @override
  bool get nestsTextSubjectInMessageSelection => true;

  @override
  bool get routesPrimaryTapToIdleMessage => true;

  @override
  bool get usesTimerBasedLongPress => true;

  @override
  bool get shiftsBubbleForSelectionGutter => true;

  @override
  bool get positionsSelectionCheckAtTrailingEdge => false;

  @override
  bool get appliesSelectedColorToBubble => false;

  @override
  bool get suppressesLinkTapInMessageSelection => true;

  @override
  bool get secondaryMessageTapOwnsFullSlot => false;

  @override
  bool get suppressesTapHighlightDuringSelection => true;

  @override
  bool get hasInteractiveCodeHeader => false;

  @override
  bool get hasBottomCodeCopyBar => true;

  @override
  bool hasBottomCodeCopyBarForLength(int length) =>
      length >= ChatSelectionPolicy.mobileCodeCopyBarThreshold;

  @override
  void applyEnterMembership({
    required void Function(Set<int> ids) replaceSelectedIds,
    required VoidCallback clearMessageSelection,
    required int messageId,
  }) {
    // Mobile text entry preserves message selection membership untouched.
  }

  @override
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  }) {
    clearTextSelection();
    clearMessageSelection();
  }
}

/// Desktop / web **selection policy**.
///
/// Direct character-range entry without prior **message selection**.
/// Text-active and message membership are mutually exclusive. Copy writes
/// the clipboard only and keeps the range. Dismiss clears text.
final class ChatSelectionPolicy$Desktop implements ChatSelectionPolicy {
  /// Creates the desktop / web policy variant.
  const ChatSelectionPolicy$Desktop();

  @override
  bool get allowsTextEntryWithoutMessageSelection => true;

  @override
  bool get routesLongPressToTextSelection => false;

  @override
  bool get nestsTextSubjectInMessageSelection => false;

  @override
  bool get routesPrimaryTapToIdleMessage => false;

  @override
  bool get usesTimerBasedLongPress => false;

  @override
  bool get shiftsBubbleForSelectionGutter => false;

  @override
  bool get positionsSelectionCheckAtTrailingEdge => true;

  @override
  bool get appliesSelectedColorToBubble => true;

  @override
  bool get suppressesLinkTapInMessageSelection => false;

  @override
  bool get secondaryMessageTapOwnsFullSlot => true;

  @override
  bool get suppressesTapHighlightDuringSelection => false;

  @override
  bool get hasInteractiveCodeHeader => true;

  @override
  bool get hasBottomCodeCopyBar => false;

  @override
  bool hasBottomCodeCopyBarForLength(int length) => false;

  @override
  void applyEnterMembership({
    required void Function(Set<int> ids) replaceSelectedIds,
    required VoidCallback clearMessageSelection,
    required int messageId,
  }) {
    clearMessageSelection();
  }

  @override
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  }) {
    // Clipboard only — keep the character range.
  }
}
