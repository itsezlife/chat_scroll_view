import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Whether the menu gesture landed on the painted **message surface**
/// (bubble chrome including header / body / meta) or only on the surrounding
/// **slot** padding / row chrome outside that surface.
///
/// The menu still opens for [outside] on a present slot; catalogs typically
/// reduce rows (desktop Select-only). Empty list / day headers never emit a
/// request.
enum ChatMessageMenuPointState {
  /// Tap is in the slot but outside the message surface (near-bubble).
  outside,

  /// Tap is inside the reported message surface (or text body when no
  /// surface was reported).
  inside,
}

/// How the gesture relates to **message selection** membership.
enum ChatMessageMenuMembership {
  /// Message selection is inactive.
  idle,

  /// Selection is active and the tap id is in the selected set (**over-selection**).
  uponSelected,

  /// Selection is active but the tap id is not in the selected set.
  elsewhere,
}

/// Structured packet the viewport emits when a message-menu entry gesture
/// wins on a present message **slot**.
///
/// Carries geometry the host needs to present chrome (id, slot, tap) plus
/// viewport-known **hit context** for choosing rows: **point state**,
/// message-selection **membership**, whether this message has a live **text
/// selection**, range-upon overlap (with optional plain-text snapshot),
/// optional **select-up-to** chain ids, and an optional **inline hit**.
/// Action and reaction catalogs stay host data per present — not fields here.
///
/// Opening a menu from this packet does not by itself clear message
/// membership or text selection.
@immutable
final class ChatMessageMenuRequest {
  /// Creates a **message menu request** for [messageId] at [slotGlobal] /
  /// [tapGlobal].
  ///
  /// When [overlapsTextSelection] is true, [selectedTextSnapshot] is the
  /// plain text of the live range (possibly empty) so Copy-selected does not
  /// race a later clear. When overlap is false, [selectedTextSnapshot] is
  /// null.
  ///
  /// [overSelection] is accepted as a shorthand for
  /// [ChatMessageMenuMembership.uponSelected] when [membership] is left at
  /// idle; prefer setting [membership] directly.
  const ChatMessageMenuRequest({
    required this.messageId,
    required this.slotGlobal,
    required this.tapGlobal,
    this.pointState = ChatMessageMenuPointState.inside,
    ChatMessageMenuMembership membership = ChatMessageMenuMembership.idle,
    bool overSelection = false,
    this.hasTextSelection = false,
    this.overlapsTextSelection = false,
    this.selectedTextSnapshot,
    this.selectUpToIds,
    this.inlineHit,
  }) : assert(
         !overlapsTextSelection || selectedTextSnapshot != null,
         'selectedTextSnapshot is required when overlapsTextSelection is true',
       ),
       assert(
         !overlapsTextSelection || hasTextSelection,
         'hasTextSelection must be true when overlapsTextSelection is true',
       ),
       assert(
         !overSelection || membership == ChatMessageMenuMembership.idle,
         'Pass membership: uponSelected instead of combining overSelection '
         'with a non-idle membership',
       ),
       membership = overSelection
           ? ChatMessageMenuMembership.uponSelected
           : membership;

  /// Present message id under the winning entry gesture.
  final int messageId;

  /// That message's full **slot** rect in global coordinates (row width ×
  /// child height — not bubble-only).
  final Rect slotGlobal;

  /// Tap / secondary-tap position in global coordinates.
  final Offset tapGlobal;

  /// Message-surface **Inside** vs slot-only **Outside**.
  final ChatMessageMenuPointState pointState;

  /// Message-selection membership relative to [messageId].
  final ChatMessageMenuMembership membership;

  /// Whether the gesture landed on a message already in the selected set
  /// while **message selection** is active (**over-selection**).
  ///
  /// Identical to [membership] == [ChatMessageMenuMembership.uponSelected].
  bool get overSelection =>
      membership == ChatMessageMenuMembership.uponSelected;

  /// Whether [messageId] is the live non-collapsed **text selection** subject
  /// (independent of whether [tapGlobal] is upon the highlight).
  ///
  /// When true and [overlapsTextSelection] is false, catalogs typically omit
  /// both Copy and Copy-selected (neither whole-message nor range copy).
  final bool hasTextSelection;

  /// Whether [tapGlobal] lands inside the live non-collapsed **text
  /// selection** highlight on [messageId] (range-upon for Copy-selected).
  final bool overlapsTextSelection;

  /// Plain text of the live text-selection range when
  /// [overlapsTextSelection] is true; otherwise null.
  final String? selectedTextSnapshot;

  /// Inclusive id chain from the nearest selected message to [messageId]
  /// when **Select up to this message** is available; otherwise null.
  ///
  /// Present only for [ChatMessageMenuMembership.elsewhere] when the span
  /// fits under [ChatSelectionController.selectionCap] (or there is no cap).
  final List<int>? selectUpToIds;

  /// Inline element under the tap when [pointState] is
  /// [ChatMessageMenuPointState.inside]; otherwise null.
  final ChatInlineHit? inlineHit;

  /// Whether [selectUpToIds] offers a usable Select-up-to row.
  bool get canSelectUpTo =>
      selectUpToIds != null && selectUpToIds!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageMenuRequest &&
      other.messageId == messageId &&
      other.slotGlobal == slotGlobal &&
      other.tapGlobal == tapGlobal &&
      other.pointState == pointState &&
      other.membership == membership &&
      other.hasTextSelection == hasTextSelection &&
      other.overlapsTextSelection == overlapsTextSelection &&
      other.selectedTextSnapshot == selectedTextSnapshot &&
      listEquals(other.selectUpToIds, selectUpToIds) &&
      other.inlineHit == inlineHit;

  @override
  int get hashCode => Object.hash(
    messageId,
    slotGlobal,
    tapGlobal,
    pointState,
    membership,
    hasTextSelection,
    overlapsTextSelection,
    selectedTextSnapshot,
    Object.hashAll(selectUpToIds ?? const <int>[]),
    inlineHit,
  );

  @override
  String toString() =>
      'ChatMessageMenuRequest('
      'messageId: $messageId, '
      'pointState: $pointState, '
      'membership: $membership, '
      'hasTextSelection: $hasTextSelection, '
      'overlapsTextSelection: $overlapsTextSelection, '
      'canSelectUpTo: $canSelectUpTo, '
      'inlineHit: $inlineHit'
      ')';
}

/// Host callback for policy-owned message-menu entry
/// ([ChatScrollView.onIdleMessageTap] / [ChatScrollView.onSecondaryMessageTap]).
typedef ChatMessageMenuRequestCallback =
    void Function(ChatMessageMenuRequest request);
