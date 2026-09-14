import 'dart:async' show unawaited;
import 'dart:collection';
import 'dart:ui' show Offset, Path, Rect;

import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_allowed.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_text_selection.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_span_feedback.dart';
import 'package:flutter/foundation.dart'
    show
        Listenable,
        ValueChanged,
        ValueListenable,
        ValueNotifier,
        VoidCallback,
        setEquals;
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart' show internal;

export 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
export 'package:chat_scroll_view/src/chat_scroll/chat_selection_allowed.dart';
export 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
export 'package:chat_scroll_view/src/chat_widgets/chat_span_feedback.dart';

/// Signature for observing active span feedback animation state.
typedef ChatSpanFeedbackCallback = void Function(ChatSpanFeedback? feedback);

/// Signature for handling a span feedback **begin** (pointer down) request.
typedef ChatSpanFeedbackTriggerCallback =
    void Function(int messageId, Path contourPath, Offset touchOrigin);

/// Signature for span feedback **release** (pointer up / cancel fade).
typedef ChatSpanFeedbackReleaseCallback = void Function();

/// Signature for span feedback **abort** (immediate clear on selection yield).
typedef ChatSpanFeedbackAbortCallback = void Function();

/// Signature for handling tapped hyperlinks in message bodies.
typedef ChatLinkTapCallback =
    void Function(int messageId, String title, String url);

/// Signature for handling long-pressed hyperlinks in message bodies.
typedef ChatLinkLongPressCallback =
    void Function(int messageId, String title, String url);

/// Signature for handling tapped code blocks or monospace code snippets.
typedef ChatCodeTapCallback = void Function(int messageId, String code);

/// Action performed during a continuous pointer drag-selection gesture on
/// desktop/web platforms.
enum ChatDragSelectAction {
  /// No drag-selection is currently active.
  none,

  /// Drag is selecting candidate messages (adding to selection).
  selecting,

  /// Drag is deselecting candidate messages (removing from selection).
  deselecting,
}

/// Public selection facade for the chat viewport: **message selection**
/// membership plus **text selection** subject, range, **selection policy**,
/// and Copy observation.
///
/// Long press enters message-selection mode and selects the message.
/// Taps toggle messages. Selection mode exits when the set empties.
/// [selectionCap] optionally limits how large the selected set can grow.
/// [selectionAllowed] optionally controls per-id membership and chrome
/// (see [ChatSelectionAllowed]).
///
/// **Text selection** is owned here (ADR 013), peer to membership, under
/// [selectionPolicy]. New call sites MUST NOT compose a second host
/// controller for subject, range, policy, or Copy. Continuous in-bubble text
/// gestures (mobile long-press → drag-extend; desktop mouse drag / multi-click)
/// are owned by the per-body markdown selection scope after the viewport
/// yields (ADR 015); this facade **adopts** the **text selection subject**
/// from the first non-collapsed markdown range. Programmatic
/// [enterTextSelection] / [armTextSelection] remain for hosts and tests.
/// The markdown library’s list selection scope is not the chat gesture authority.
///
/// Lives outside the render tree — survives render eviction and can be
/// queried by external UI (toolbar, copy button). Implements [Listenable]
/// so the widget-based viewport can drive `ListenableBuilder` directly.
/// [Listenable] fires on membership **or** text-selection subject/range
/// changes. Copy success uses [addCopySuccessListener] (and optional
/// [onCopySuccess]); feedback UI stays app-side.
///
/// ### Swapping conversations
///
/// Selection is a bare `Set<int>` of message ids — it has no notion of
/// *which* conversation those ids belong to. When the consumer swaps the
/// `ChatDataSource` (e.g. opening a different chat thread on the same
/// viewport) the previously-selected ids stay in the set and will now
/// silently match unrelated messages in the new conversation. Call [clear]
/// from your own dataSource-swap logic, or scope a separate
/// [ChatSelectionController] per conversation, to avoid this footgun.
///
/// ### Changing [selectionAllowed]
///
/// Assigning [selectionAllowed] (or calling
/// [reapplySelectionAllowed]) drops any selected id that is no longer
/// selectable and notifies [addSelectionAllowedListener] so the
/// viewport can rebuild selection chrome. Mutating state closed over by the
/// predicate without reassigning or calling [reapplySelectionAllowed]
/// does not notify — chrome wrap may stay stale until the next natural
/// layout that re-evaluates selection-allowed.
///
/// ### Inline hits (links and code)
///
/// Inline body hits (hyperlinks and fenced code / monospace snippets) participate
/// in engine gesture arbitration. Tapping a link or code snippet is a first-class
/// interaction: it is not swallowed as an idle-tap selection dismiss or idle message
/// tap.
///
/// Under [$Mobile], **message selection** or a live **character-range text
/// selection** suppresses *all* inline activations (links, inline code, fenced
/// COPY chrome) so row toggles / range ownership win. Idle (no message
/// membership and no live range) keeps link and code/COPY first-class. Mere
/// desktop arm-for-entry does not suppress. Under [$Desktop], message
/// membership does not suppress inline activation.
///
/// Code taps **and idle long-presses** trigger click-to-copy (clipboard write
/// plus [addCopySuccessListener]), and notify [addCodeTapListener]. Automatic
/// clipboard write can be disabled via [copyCodeOnClick]. Under suppression
/// (mobile message selection / live text range), long-press yields to message
/// or text selection instead.
///
/// ### Policy
///
/// [selectionPolicy] is fixed at construction. Hosts MUST NOT expect to
/// swap the matrix on a live facade — construct a new controller.
class ChatSelectionController implements Listenable {
  /// Creates a selection facade.
  ///
  /// [policy] defaults to [ChatSelectionPolicy.forPlatform].
  ChatSelectionController({
    ChatSelectionPolicy? policy,
    this.onCopySuccess,
    this.onLinkTap,
    this.onLinkLongPress,
    this.onCodeTap,
    this.copyCodeOnClick = true,
  }) : selectionPolicy = policy ?? ChatSelectionPolicy.forPlatform(),
       _text = ChatTextSelection(
         policy: policy ?? ChatSelectionPolicy.forPlatform(),
       ) {
    _text.markdownSelection.addListener(_onTextRangeChanged);
  }

  /// Active **selection policy** (entry, nesting, Copy).
  final ChatSelectionPolicy selectionPolicy;

  /// Optional host hook invoked after a successful Copy clipboard write.
  ///
  /// Receives the copied plain text. Prefer [addCopySuccessListener] when
  /// multiple observers need the same event.
  final ValueChanged<String>? onCopySuccess;

  /// Optional host hook invoked when a hyperlink in a markdown body is tapped.
  ///
  /// Receives `(messageId, title, url)`. Prefer [addLinkTapListener] when
  /// multiple observers need the same event.
  final ChatLinkTapCallback? onLinkTap;

  /// Optional host hook invoked when a hyperlink in a markdown body is long-pressed.
  ///
  /// Receives `(messageId, title, url)`. Prefer [addLinkLongPressListener] when
  /// multiple observers need the same event.
  final ChatLinkLongPressCallback? onLinkLongPress;

  /// Optional host hook invoked when a code block or monospace snippet is tapped.
  ///
  /// Receives `(messageId, code)`. Prefer [addCodeTapListener] when multiple
  /// observers need the same event.
  final ChatCodeTapCallback? onCodeTap;

  /// Whether tapping a code block or monospace snippet automatically writes
  /// the code text to the system clipboard and notifies Copy-success observers.
  ///
  /// Defaults to `true`. When `false`, [onCodeTap] and code tap listeners are
  /// still notified, but no clipboard write or [onCopySuccess] notification occurs.
  final bool copyCodeOnClick;

  final ChatTextSelection _text;
  final _copySuccessListeners = <ValueChanged<String>>[];
  final _linkTapListeners = <ChatLinkTapCallback>[];
  final _linkLongPressListeners = <ChatLinkLongPressCallback>[];
  final _codeTapListeners = <ChatCodeTapCallback>[];

  final _selectedIds = HashSet<int>();
  Set<int>? _dragSelectedIds;
  ChatDragSelectAction _dragSelectAction = ChatDragSelectAction.none;
  final _capHits = ValueNotifier<int>(0);
  final _selectionAllowedListeners = <VoidCallback>[];

  /// The active drag-selection action (selecting, deselecting, or none).
  ChatDragSelectAction get dragSelectAction => _dragSelectAction;

  /// Whether an uncommitted drag-selection preview is currently active.
  bool get hasDragSelection =>
      _dragSelectedIds != null &&
      _dragSelectedIds!.isNotEmpty &&
      _dragSelectAction != ChatDragSelectAction.none;

  /// Uncommitted drag-selected message IDs (unmodifiable view), or null when
  /// no drag selection is live.
  Set<int>? get dragSelectedIds => _dragSelectedIds == null
      ? null
      : UnmodifiableSetView<int>(_dragSelectedIds!);

  /// Whether selection mode is active (either through committed message
  /// selection or live drag-selection preview).
  bool get isSelectionMode => _selectedIds.isNotEmpty || hasDragSelection;

  /// The number of selected messages (including live drag-selection preview).
  int get count => effectiveSelectedIds.length;

  /// The set of selected message IDs (unmodifiable view of committed selection).
  Set<int> get selectedIds => UnmodifiableSetView<int>(_selectedIds);

  /// Effective selected message IDs including live drag preview.
  Set<int> get effectiveSelectedIds {
    if (!hasDragSelection) {
      return _selectedIds;
    }
    if (_dragSelectAction == ChatDragSelectAction.deselecting) {
      return _selectedIds.difference(_dragSelectedIds!);
    }
    final combined = {..._selectedIds, ..._dragSelectedIds!};
    if (selectionCap != null && combined.length > selectionCap!) {
      return combined.take(selectionCap!).toSet();
    }
    return combined;
  }

  /// Whether [messageId] is in the committed or drag-preview selection.
  bool isSelected(int messageId) {
    if (hasDragSelection && _dragSelectedIds!.contains(messageId)) {
      if (_dragSelectAction == ChatDragSelectAction.deselecting) {
        return false;
      }
      return effectiveSelectedIds.contains(messageId);
    }
    return _selectedIds.contains(messageId);
  }

  /// Updates the uncommitted drag-selection preview with [ids].
  ///
  /// Used on desktop/web during continuous pointer drag selection to preview
  /// selecting or deselecting candidate messages before commit.
  void updateDragSelection(
    Set<int> ids, {
    ChatDragSelectAction action = ChatDragSelectAction.selecting,
  }) {
    if (_disposed) return;
    final filtered = ids.where(isSelectable).toSet();
    if (filtered.isEmpty) {
      clearDragSelection();
      return;
    }
    if (setEquals(_dragSelectedIds, filtered) && _dragSelectAction == action) {
      return;
    }
    _dragSelectedIds = filtered;
    _dragSelectAction = action;
    _notify();
  }

  /// Clears the uncommitted drag-selection preview.
  ///
  /// Restores visual focus to text selection (if active) or base message
  /// selection when the mouse pointer returns within drag slop.
  void clearDragSelection() {
    if (_disposed ||
        (_dragSelectedIds == null &&
            _dragSelectAction == ChatDragSelectAction.none)) {
      return;
    }
    _dragSelectedIds = null;
    _dragSelectAction = ChatDragSelectAction.none;
    _notify();
  }

  /// Commits the uncommitted drag-selection preview into permanent [selectedIds].
  ///
  /// Clears active text selection and exits text mode, locking into message
  /// selection mode.
  void applyDragSelection() {
    if (_disposed) return;
    final drag = _dragSelectedIds;
    final action = _dragSelectAction;
    _dragSelectedIds = null;
    _dragSelectAction = ChatDragSelectAction.none;
    if (drag == null || drag.isEmpty || action == ChatDragSelectAction.none) {
      return;
    }
    if (_text.isActive) {
      _hasEstablishedTextRange = false;
      _text.disarm();
    }
    if (action == ChatDragSelectAction.selecting) {
      for (final id in drag) {
        if (selectionCap != null && _selectedIds.length >= selectionCap!) {
          notifyCapHit();
          break;
        }
        _selectedIds.add(id);
      }
    } else if (action == ChatDragSelectAction.deselecting) {
      _selectedIds.removeAll(drag);
    }
    _onMembershipChanged();
    _notify();
  }

  /// Enter selection mode and select [messageId].
  ///
  /// No-op when [messageId] is already selected, is not selectable, or when
  /// adding it would exceed [selectionCap].
  void startSelection(int messageId) {
    if (_disposed || !isSelectable(messageId)) return;
    if (_text.isActive) {
      clearTextSelection();
    }
    if (_selectedIds.contains(messageId)) return;
    if (isAtSelectionCap) {
      notifyCapHit();
      return;
    }
    _selectedIds.add(messageId);
    _onMembershipChanged();
    _notify();
  }

  /// Toggle [messageId] in/out of selection.
  /// Exits selection mode when the set becomes empty.
  ///
  /// Adding is a no-op when [messageId] is not selectable or the set is
  /// already at [selectionCap].
  void toggle(int messageId) {
    if (_disposed) return;
    if (_text.isActive) {
      clearTextSelection();
    }
    if (_selectedIds.remove(messageId)) {
      _onMembershipChanged();
      _notify();
      return;
    }
    if (!isSelectable(messageId)) return;
    if (isAtSelectionCap) {
      notifyCapHit();
      return;
    }
    _selectedIds.add(messageId);
    _onMembershipChanged();
    _notify();
  }

  /// Clear all selection. Exits selection mode.
  ///
  /// Visual chrome freezes selected-progress on each row and only animates
  /// mode closed — see [SelectableMessage]. Empties the set and clears
  /// markdown text selection if active.
  void clear() {
    if (_disposed) return;
    final hadDrag = _dragSelectedIds != null;
    _dragSelectedIds = null;
    final hadSelected = _selectedIds.isNotEmpty;
    _selectedIds.clear();
    final textChanged = _text.disarm();
    _hasEstablishedTextRange = false;
    _pendingWordSelect = false;
    if (hadSelected || hadDrag || textChanged) {
      _notify();
    }
  }

  /// Cancels the active selection kind.
  ///
  /// Dismisses the most specific active selection mode:
  /// - When **text selection** is active ([isTextSelectionActive]), clears text
  ///   selection and leaves message selection untouched. Under mobile policy,
  ///   this preserves the selected messages set; under desktop/web policy,
  ///   message membership is already empty due to mode exclusivity.
  /// - When text selection is inactive and **message selection** is active
  ///   ([isSelectionMode]), clears message selection.
  ///
  /// Returns `true` if an active selection was cancelled, or `false` if
  /// neither text nor message selection was active (or after [dispose]).
  bool cancelSelection() {
    if (_disposed) return false;
    if (_text.isActive) {
      clearTextSelection();
      return true;
    }
    if (_selectedIds.isNotEmpty) {
      clear();
      return true;
    }
    return false;
  }

  /// Replaces the selected set with [ids]. No-op if equal. Empty [ids]
  /// exits selection mode. Ids that are not selectable are omitted.
  void replaceSelectedIds(Set<int> ids) {
    if (_disposed) return;
    final next = _selectionAllowed == null
        ? ids
        : ids.where(isSelectable).toSet();
    if (next.length == _selectedIds.length && _selectedIds.containsAll(next)) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(next);
    _onMembershipChanged();
    _notify();
  }

  void _clearMessageIds() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _notify();
  }

  void _resetTextSelection() {
    _text.disarm();
    _hasEstablishedTextRange = false;
    _pendingWordSelect = false;
  }

  void _onMembershipChanged() {
    if (_disposed || !_text.isActive) return;
    final subject = _text.subjectId;
    if (selectionPolicy.nestsTextSubjectInMessageSelection) {
      if (subject == null || !isSelected(subject)) {
        _resetTextSelection();
      }
    } else if (_selectedIds.isNotEmpty) {
      _resetTextSelection();
    }
  }

  // --- Text selection ---

  /// Whether character-range **text selection** is active for
  /// [textSelectionSubject].
  bool get isTextSelectionActive => _text.isActive;

  /// Message ID of the active **text selection subject**, or null when
  /// inactive.
  int? get textSelectionSubject => _text.subjectId;

  /// Character-range on the markdown selection model, or null when none.
  ///
  /// Endpoints stay on one message. A collapsed or missing range is not
  /// an active copyable selection.
  MarkdownSelection? get textSelection => _text.range;

  /// Markdown selection model used by this facade.
  ///
  /// Viewport / body mounts only. Hosts MUST observe [textSelection] /
  /// [textSelectionSubject] instead of driving this controller as a second
  /// public API.
  @internal
  MarkdownSelectionController get markdownSelection => _text.markdownSelection;

  /// Inserts or updates the markdown body for [messageId].
  ///
  /// Returns an ownership token. Pass it back on later updates and to
  /// [removeBody]. Several mounts may share one [messageId]; only the last
  /// [removeBody] drops the registry entry. Silent after [dispose].
  Object? putBody(int messageId, Markdown model, {int? order, Object? token}) =>
      _text.putBody(messageId, model, order: order, token: token);

  /// Registers [model] for [messageId]. Convenience alias for [putBody].
  Object? registerBody(
    int messageId,
    Markdown model, {
    int? order,
    Object? token,
  }) => putBody(messageId, model, order: order, token: token);

  /// Returns the mounted [MarkdownSelectionSurface] for [messageId], if any.
  MarkdownSelectionSurface? surfaceFor(int messageId) =>
      _text.surfaceFor(messageId);

  /// Whether [globalOffset] hits the selectable body text of [messageId].
  ///
  /// Returns `false` when disposed, no body is registered for [messageId],
  /// or hit-testing against registered selectable document surfaces misses
  /// that message’s text.
  bool containsGlobal(int messageId, Offset globalOffset) =>
      _text.containsGlobal(messageId, globalOffset);

  /// Whether [messageId] is the live non-collapsed **text selection** subject.
  bool hasTextSelectionOnMessage(int messageId) {
    if (_disposed || !_text.isActive || _text.subjectId != messageId) {
      return false;
    }
    final range = _text.range;
    return range != null && !range.isCollapsed;
  }

  /// Whether a **message menu** for [messageId] at [globalOffset] should
  /// report live **text selection** overlap for Copy-selected.
  ///
  /// True when text selection is active, non-collapsed, [messageId] is the
  /// **text selection subject**, and [globalOffset] lands inside a painted
  /// selection highlight rect. Subject-only (tap elsewhere on the same
  /// message) returns false.
  bool textSelectionOverlapsMessage(int messageId, Offset globalOffset) {
    if (_disposed) return false;
    return _text.textSelectionContainsGlobal(messageId, globalOffset);
  }

  /// Plain text of the live **text selection** range, or `null` when
  /// disposed, inactive, collapsed, or empty.
  String? textSelectionPlainText() {
    if (_disposed || !_text.isActive) return null;
    final range = _text.range;
    if (range == null || range.isCollapsed) return null;
    final text = _text.getText();
    return text.isEmpty ? null : text;
  }

  /// Removes a previously registered body.
  ///
  /// When [token] is non-null, drops only that owner. When [messageId] is
  /// the active subject and the entry is fully removed, clears **text
  /// selection**. Silent after [dispose].
  void removeBody(int messageId, {Object? token}) {
    if (_text.removeBody(messageId, token: token)) {
      _notify();
    }
  }

  /// Enters **text selection** for [messageId] under [selectionPolicy].
  ///
  /// Mobile: requires an already-selected [messageId]. Preserves existing
  /// message selection membership intact. Desktop: allows entry without prior
  /// membership and clears the selected set (exclusive).
  ///
  /// When [globalOffset] is non-null, selects the word at that point after
  /// the next frame (surface attach). When [globalOffset] is null, selects
  /// the entire subject body on the markdown model immediately.
  ///
  /// Programmatic / test entry only — mobile gesture entry is owned by the
  /// per-body markdown scope after the viewport yields (ADR 015).
  ///
  /// Returns `false` when disposed, entry is blocked by policy / missing
  /// body, or (without [globalOffset]) select-all produced no range.
  /// Pre-arm failures leave prior text-selection state unchanged.
  bool enterTextSelection(int messageId, {Offset? globalOffset}) {
    if (_disposed) return false;
    if (!selectionPolicy.allowsTextEntryWithoutMessageSelection &&
        !isSelected(messageId)) {
      return false;
    }
    _hasEstablishedTextRange = false;
    if (!_text.arm(messageId)) return false;

    if (globalOffset == null) {
      final selected = _text.selectAllSubject();
      if (!selected) {
        _text.disarm();
        return false;
      }
      _hasEstablishedTextRange = true;
      selectionPolicy.applyEnterMembership(
        replaceSelectedIds: replaceSelectedIds,
        clearMessageSelection: _clearMessageIds,
        messageId: messageId,
      );
      return true;
    }

    return _scheduleWordAtGlobal(messageId, globalOffset);
  }

  /// Arms [messageId] as the active text selection subject without immediately
  /// selecting a range, enabling direct desktop mouse click/drag and multi-click
  /// text selection gestures.
  ///
  /// Pre-arm failures leave prior text selection state unchanged.
  /// Under desktop/web policy, refuses while **message selection** is active
  /// (modes are exclusive; tdesktop does not start character selection once
  /// message multi-select is settled).
  bool armTextSelection(int messageId) {
    if (_disposed) return false;
    if (selectionPolicy.allowsTextEntryWithoutMessageSelection &&
        isSelectionMode) {
      return false;
    }
    if (!selectionPolicy.allowsTextEntryWithoutMessageSelection &&
        !isSelected(messageId)) {
      return false;
    }
    if (_text.isActive && _text.subjectId == messageId) {
      return true;
    }
    _hasEstablishedTextRange = false;
    if (!_text.arm(messageId)) return false;
    selectionPolicy.applyEnterMembership(
      replaceSelectedIds: replaceSelectedIds,
      clearMessageSelection: _clearMessageIds,
      messageId: messageId,
    );
    _notify();
    return true;
  }

  /// Selects the entire text of the currently armed text selection subject.
  ///
  /// Returns `false` when text selection is not active, disposed, or select-all
  /// produces no range. Marks toolbar as wanted so mounted selection chrome
  /// reveals the context menu.
  bool selectAllText() {
    if (_disposed || !_text.isActive) return false;
    final selected = _text.selectAllSubject();
    if (selected) {
      _hasEstablishedTextRange = true;
      _text.markdownSelection.toolbarWanted = true;
      _notify();
    }
    return selected;
  }

  bool _scheduleWordAtGlobal(int messageId, Offset globalOffset) {
    _pendingWordSelect = true;
    // Rebuild bodies so MarkdownSelectionScope.enabled flips on before the
    // word range lands (handles / toolbar sync need an enabled scope).
    _notify();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_text.isActive || _text.subjectId != messageId) {
        _pendingWordSelect = false;
        return;
      }
      // selectWordAtGlobal uses _commitSelection, which does not set
      // toolbarWanted (gesture path expects showToolbar on press-end). Host
      // entry with enableTouchGestures: false never gets that press-end —
      // mark toolbar wanted before commit so the scope listener reveals it.
      if (selectionPolicy.usesTimerBasedLongPress) {
        _text.markdownSelection.toolbarWanted = true;
      }
      final sel = _text.selectWordAtGlobal(globalOffset);
      _pendingWordSelect = false;
      if (sel == null) {
        clearTextSelection();
      } else {
        _hasEstablishedTextRange = true;
        selectionPolicy.applyEnterMembership(
          replaceSelectedIds: replaceSelectedIds,
          clearMessageSelection: _clearMessageIds,
          messageId: messageId,
        );
        _notify();
      }
    });
    return true;
  }

  /// Clears markdown **text selection** and disarms the subject.
  ///
  /// Leaves [selectedIds] unchanged. Silent when already inactive with no
  /// range, or after [dispose].
  void clearTextSelection() {
    if (_disposed || _isDisarming) return;
    _hasEstablishedTextRange = false;
    _pendingWordSelect = false;
    _isDisarming = true;
    try {
      if (!_text.disarm()) return;
    } finally {
      _isDisarming = false;
    }
    _notify();
  }

  /// Whether a markdown body for [messageId] should mount a selectable document
  /// surface with [markdownSelection].
  ///
  /// Under mobile policy: while **text selection** is inactive, every
  /// registered body exposes a surface when idle or message-selected (inline
  /// hit-testing and long-press entry). While text is live, only the
  /// [textSelectionSubject] mounts — sibling selected mounts share this
  /// controller and would `putDocument` on attach, re-expanding the registry
  /// and breaking Select All / one-message ranges. Retarget uses reported
  /// body paint bounds plus facade [enterTextSelection].
  ///
  /// Under desktop direct-entry: every registered body while idle **and** while
  /// **message selection** is active (inline link/code/chrome activation must
  /// keep working without unmounting hit targets). While text-active on
  /// desktop: only the active [textSelectionSubject].
  bool exposesSelectionSurface(int messageId) {
    if (_disposed) return false;
    if (!_text.hasBody(messageId)) return false;
    if (selectionPolicy.nestsTextSubjectInMessageSelection) {
      if (_text.isActive) return _text.subjectId == messageId;
      return isSelected(messageId) || _selectedIds.isEmpty;
    }
    if (_text.isActive) return _text.subjectId == messageId;
    if (selectionPolicy.allowsTextEntryWithoutMessageSelection) {
      // Idle direct entry and message-selection inline hits both need mounts.
      // Live drag-preview alone does not unmount — hit-testing stays live.
      return true;
    }
    return false;
  }

  /// Records the body widget's [RenderBox] for [containsGlobal] fallback.
  ///
  /// Bodies call this so [containsGlobal] / retarget still work when the
  /// selection surface is unmounted for non-subjects. Pass `null` on unmount.
  /// Hit-tests resolve live global geometry at query time (scroll-safe).
  void reportBodyPaintBounds(int messageId, RenderBox? box) {
    if (_disposed) return;
    _text.reportBodyPaintBounds(messageId, box);
  }

  /// Records the painted **message surface** (bubble chrome) [RenderBox] for
  /// [containsMessageSurface] / message-menu **point state**.
  ///
  /// Hosts wrap the bubble in [ChatMessageSurfaceBounds] (or call this
  /// directly). Pass `null` on unmount. Hit-tests resolve
  /// [RenderBox.localToGlobal] at query time so scroll without rebuild stays
  /// correct — do not cache a global [Rect] across frames.
  void reportMessageSurfaceBounds(int messageId, RenderBox? box) {
    if (_disposed) return;
    _text.reportMessageSurfaceBounds(messageId, box);
  }

  /// Whether [globalOffset] hits the reported message surface for
  /// [messageId], falling back to the text body when no surface was reported.
  bool containsMessageSurface(int messageId, Offset globalOffset) =>
      _text.containsMessageSurface(messageId, globalOffset);

  /// Registered markdown model for [messageId], or null when none.
  Markdown? bodyOf(int messageId) => _text.bodyOf(messageId);

  /// Whether [messageId] has at least one registered markdown body.
  bool hasBody(int messageId) => _text.hasBody(messageId);

  /// Whether [messageId] is currently the armed text-selection subject.
  bool isDocumentArmed(int messageId) => _text.isDocumentArmed(messageId);

  bool _isCopying = false;

  /// Copies the active plain-text range, then applies [selectionPolicy]
  /// Copy-success effects and notifies Copy-success observers.
  ///
  /// Returns `false` when disposed, text selection is inactive, or there is
  /// no non-empty range (state unchanged; no Copy-success notify).
  Future<bool> copyTextSelection() async {
    if (_disposed || !_text.isActive || _isCopying) return false;
    final text = _text.getText();
    if (text.isEmpty) return false;
    final currentSubject = _text.subjectId;
    _isCopying = true;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } finally {
      _isCopying = false;
    }
    if (_disposed || !_text.isActive || _text.subjectId != currentSubject) {
      return false;
    }
    selectionPolicy.applyCopySuccess(
      clearTextSelection: clearTextSelection,
      clearMessageSelection: clear,
    );
    _notifyCopySuccess(text);
    return true;
  }

  /// Registers [listener] for successful Copy (clipboard write completed).
  ///
  /// Dedup-on-add; snapshot dispatch. Payload is the copied plain text.
  /// Silent when [copyTextSelection] returns `false`. Post-[dispose]
  /// registration is a no-op.
  void addCopySuccessListener(ValueChanged<String> listener) {
    if (_disposed) return;
    if (_copySuccessListeners.contains(listener)) return;
    _copySuccessListeners.add(listener);
  }

  /// Removes a listener registered with [addCopySuccessListener].
  void removeCopySuccessListener(ValueChanged<String> listener) {
    _copySuccessListeners.remove(listener);
  }

  void _notifyCopySuccess(String text) {
    onCopySuccess?.call(text);
    for (final cb in List<ValueChanged<String>>.of(
      _copySuccessListeners,
      growable: false,
    )) {
      cb(text);
    }
  }

  // --- Inline hits (links & code) ---

  /// Resolves whether [globalOffset] hits an inline element (hyperlink or
  /// code block / monospace snippet) in the registered body of [messageId].
  ///
  /// Returns a [ChatInlineHit] descriptor when an inline element is hit,
  /// or `null` when the point lands on unformatted plain text, padding,
  /// or outside mounted body text.
  ChatInlineHit? resolveInlineHit(int messageId, Offset globalOffset) =>
      _text.resolveInlineHit(messageId, globalOffset);

  /// Resolves an inline hit at a logical [blockIndex] and rendered-text [offset]
  /// for [messageId].
  ///
  /// Pure model query without render tree dependencies. Returns [ChatInlineHit$Link]
  /// for hyperlink spans, [ChatInlineHit$Code] for monospace spans or interactive
  /// fenced code blocks (when [isHeader] or [isBottomBar] is true), or `null` for
  /// unformatted/plain text or fenced code bodies (which delegate to text selection).
  ChatInlineHit? inlineHitAt({
    required int messageId,
    required int blockIndex,
    required int offset,
    bool isHeader = false,
    bool isBottomBar = false,
  }) => _text.inlineHitAt(
    messageId: messageId,
    blockIndex: blockIndex,
    offset: offset,
    isHeader: isHeader,
    isBottomBar: isBottomBar,
  );

  /// Dispatches an inline hit (link activation or code click-to-copy).
  ///
  /// Returns `true` if the inline hit was handled as a first-class action,
  /// or `false` if it was suppressed by policy (e.g. mobile message selection
  /// mode suppressing ordinary link opens) or after [dispose].
  ///
  /// Handled inline hits do not dismiss active text selection, do not toggle
  /// message selection membership, and do not fire idle message taps.
  bool handleInlineHit(ChatInlineHit hit) {
    if (_disposed) return false;
    // One gate for every [ChatInlineHit] variant — do not special-case link
    // vs code/COPY chrome (that flip-flops idle vs selected behavior).
    if (_suppressesInlineActivation()) {
      return false;
    }
    switch (hit) {
      case ChatInlineHit$Link(:final messageId, :final title, :final url):
        // Press ink arms on pointer down via [beginSpanFeedback]; do not
        // one-shot flash again on action.
        _notifyLinkTap(messageId, title, url);
        return true;

      case ChatInlineHit$Code(:final messageId, :final code):
        if (copyCodeOnClick) {
          unawaited(
            Clipboard.setData(ClipboardData(text: code)).catchError((_) {}),
          );
          _notifyCopySuccess(code);
        }
        _notifyCodeTap(messageId, code);
        return true;
    }
  }

  /// Whether link / inline-code / fenced COPY chrome taps must not activate.
  ///
  /// Suppresses when a **non-collapsed** character-range is live (not merely
  /// desktop arm-for-entry), or under mobile **message selection** mode.
  bool _suppressesInlineActivation() {
    if (_hasLiveTextRange) return true;
    return selectionPolicy.suppressesLinkTapInMessageSelection &&
        isSelectionMode;
  }

  /// True when the facade owns a copyable character-range (not arm-only).
  bool get _hasLiveTextRange => switch (_text.range) {
    final sel? when !sel.isCollapsed => true,
    _ => false,
  };

  /// Registers [listener] for inline hyperlink taps.
  ///
  /// Dedup-on-add; snapshot dispatch. Receives `(messageId, title, url)`.
  /// Silent when link tap is suppressed by policy or after [dispose].
  void addLinkTapListener(ChatLinkTapCallback listener) {
    if (_disposed || _linkTapListeners.contains(listener)) return;
    _linkTapListeners.add(listener);
  }

  /// Removes a listener registered with [addLinkTapListener].
  void removeLinkTapListener(ChatLinkTapCallback listener) {
    _linkTapListeners.remove(listener);
  }

  void _notifyLinkTap(int messageId, String title, String url) {
    onLinkTap?.call(messageId, title, url);
    for (final cb in List<ChatLinkTapCallback>.of(
      _linkTapListeners,
      growable: false,
    )) {
      cb(messageId, title, url);
    }
  }

  /// Dispatches an inline element long-press.
  ///
  /// Links notify [onLinkLongPress] / [addLinkLongPressListener] (preview sheet,
  /// etc.) and leave press ink until pointer up. Code / COPY chrome reuses
  /// [handleInlineHit] so hold-to-copy matches tap-to-copy (including
  /// [copyCodeOnClick] and activation suppression), then [abortSpanFeedback]
  /// so the highlight does not linger after the action.
  ///
  /// Returns `true` if the long-press was handled and should suppress message
  /// selection entry.
  bool handleInlineHitLongPress(ChatInlineHit hit) {
    if (_disposed) return false;
    switch (hit) {
      case ChatInlineHit$Link(:final messageId, :final title, :final url):
        final hasHandlers =
            onLinkLongPress != null || _linkLongPressListeners.isNotEmpty;
        _notifyLinkLongPress(messageId, title, url);
        return hasHandlers;
      case ChatInlineHit$Code():
        // Same action as tap. Drop press ink immediately — the gesture already
        // completed (unlike link long-press, which keeps ink until pointer up).
        final handled = handleInlineHit(hit);
        if (handled) abortSpanFeedback();
        return handled;
    }
  }

  /// Registers [listener] for inline hyperlink long-presses.
  ///
  /// Dedup-on-add; snapshot dispatch. Receives `(messageId, title, url)`.
  /// Silent after [dispose].
  void addLinkLongPressListener(ChatLinkLongPressCallback listener) {
    if (_disposed || _linkLongPressListeners.contains(listener)) return;
    _linkLongPressListeners.add(listener);
  }

  /// Removes a listener registered with [addLinkLongPressListener].
  void removeLinkLongPressListener(ChatLinkLongPressCallback listener) {
    _linkLongPressListeners.remove(listener);
  }

  void _notifyLinkLongPress(int messageId, String title, String url) {
    onLinkLongPress?.call(messageId, title, url);
    for (final cb in List<ChatLinkLongPressCallback>.of(
      _linkLongPressListeners,
      growable: false,
    )) {
      cb(messageId, title, url);
    }
  }

  /// Registers [listener] for inline code / monospace snippet taps.
  ///
  /// Dedup-on-add; snapshot dispatch. Receives `(messageId, code)`.
  /// Silent after [dispose].
  void addCodeTapListener(ChatCodeTapCallback listener) {
    if (_disposed || _codeTapListeners.contains(listener)) return;
    _codeTapListeners.add(listener);
  }

  /// Removes a listener registered with [addCodeTapListener].
  void removeCodeTapListener(ChatCodeTapCallback listener) {
    _codeTapListeners.remove(listener);
  }

  void _notifyCodeTap(int messageId, String code) {
    onCodeTap?.call(messageId, code);
    for (final cb in List<ChatCodeTapCallback>.of(
      _codeTapListeners,
      growable: false,
    )) {
      cb(messageId, code);
    }
  }

  ChatSpanFeedback? _spanFeedback;

  /// Currently active span feedback animation, or null when idle.
  ChatSpanFeedback? get spanFeedback => _spanFeedback;

  final _spanFeedbackListeners = <ChatSpanFeedbackCallback>[];
  final _spanFeedbackTriggerListeners = <ChatSpanFeedbackTriggerCallback>[];
  final _spanFeedbackReleaseListeners = <ChatSpanFeedbackReleaseCallback>[];
  final _spanFeedbackAbortListeners = <ChatSpanFeedbackAbortCallback>[];

  /// Registers [listener] for active span feedback changes.
  ///
  /// Dedup-on-add; snapshot dispatch. Receives the active [ChatSpanFeedback]
  /// or null when feedback clears. Silent after [dispose].
  void addSpanFeedbackListener(ChatSpanFeedbackCallback listener) {
    if (_disposed || _spanFeedbackListeners.contains(listener)) return;
    _spanFeedbackListeners.add(listener);
  }

  /// Removes a listener registered with [addSpanFeedbackListener].
  void removeSpanFeedbackListener(ChatSpanFeedbackCallback listener) {
    _spanFeedbackListeners.remove(listener);
  }

  void _notifySpanFeedback(ChatSpanFeedback? feedback) {
    for (final cb in List<ChatSpanFeedbackCallback>.of(
      _spanFeedbackListeners,
      growable: false,
    )) {
      cb(feedback);
    }
  }

  /// Registers [listener] for span feedback **begin** (press down) requests.
  ///
  /// Dedup-on-add; snapshot dispatch. Receives `(messageId, contourPath, touchOrigin)`.
  /// Silent after [dispose].
  void addSpanFeedbackTriggerListener(
    ChatSpanFeedbackTriggerCallback listener,
  ) {
    if (_disposed || _spanFeedbackTriggerListeners.contains(listener)) return;
    _spanFeedbackTriggerListeners.add(listener);
  }

  /// Removes a listener registered with [addSpanFeedbackTriggerListener].
  void removeSpanFeedbackTriggerListener(
    ChatSpanFeedbackTriggerCallback listener,
  ) {
    _spanFeedbackTriggerListeners.remove(listener);
  }

  void _notifySpanFeedbackTrigger(
    int messageId,
    Path contourPath,
    Offset touchOrigin,
  ) {
    for (final cb in List<ChatSpanFeedbackTriggerCallback>.of(
      _spanFeedbackTriggerListeners,
      growable: false,
    )) {
      cb(messageId, contourPath, touchOrigin);
    }
  }

  /// Registers [listener] for span feedback **release** (fade) requests.
  void addSpanFeedbackReleaseListener(
    ChatSpanFeedbackReleaseCallback listener,
  ) {
    if (_disposed || _spanFeedbackReleaseListeners.contains(listener)) return;
    _spanFeedbackReleaseListeners.add(listener);
  }

  /// Removes a listener registered with [addSpanFeedbackReleaseListener].
  void removeSpanFeedbackReleaseListener(
    ChatSpanFeedbackReleaseCallback listener,
  ) {
    _spanFeedbackReleaseListeners.remove(listener);
  }

  void _notifySpanFeedbackRelease() {
    for (final cb in List<ChatSpanFeedbackReleaseCallback>.of(
      _spanFeedbackReleaseListeners,
      growable: false,
    )) {
      cb();
    }
  }

  /// Registers [listener] for span feedback **abort** (immediate clear).
  void addSpanFeedbackAbortListener(ChatSpanFeedbackAbortCallback listener) {
    if (_disposed || _spanFeedbackAbortListeners.contains(listener)) return;
    _spanFeedbackAbortListeners.add(listener);
  }

  /// Removes a listener registered with [addSpanFeedbackAbortListener].
  void removeSpanFeedbackAbortListener(ChatSpanFeedbackAbortCallback listener) {
    _spanFeedbackAbortListeners.remove(listener);
  }

  void _notifySpanFeedbackAbort() {
    for (final cb in List<ChatSpanFeedbackAbortCallback>.of(
      _spanFeedbackAbortListeners,
      growable: false,
    )) {
      cb();
    }
  }

  /// Whether inline **tap highlight** may arm for the current selection state.
  ///
  /// Under mobile policy, returns `false` while **message selection** mode or
  /// **text selection** is active. Desktop always allows arming.
  bool get allowsInlineTapHighlight {
    if (!selectionPolicy.suppressesTapHighlightDuringSelection) {
      return true;
    }
    return !isSelectionMode && !isTextSelectionActive;
  }

  /// Begins press-lifecycle span feedback (pointer down on a pressable hit).
  ///
  /// Bodies listen via [addSpanFeedbackTriggerListener] and own the
  /// [AnimationController]s. Silent after [dispose], or when
  /// [allowsInlineTapHighlight] is false.
  void beginSpanFeedback({
    required int messageId,
    required Path contourPath,
    required Offset touchOrigin,
  }) {
    if (_disposed || !allowsInlineTapHighlight) return;
    _notifySpanFeedbackTrigger(messageId, contourPath, touchOrigin);
  }

  /// Alias for [beginSpanFeedback] (press-down arming).
  void triggerSpanFeedback({
    required int messageId,
    required Path contourPath,
    required Offset touchOrigin,
  }) => beginSpanFeedback(
    messageId: messageId,
    contourPath: contourPath,
    touchOrigin: touchOrigin,
  );

  /// Releases active span feedback into the fade-out phase (pointer up).
  ///
  /// Bodies complete expand if needed (min hold), then run release fade.
  /// Silent after [dispose].
  void releaseSpanFeedback() {
    if (_disposed) return;
    _notifySpanFeedbackRelease();
  }

  /// Aborts active span feedback immediately (selection / span yield).
  ///
  /// No release fade. Silent after [dispose].
  void abortSpanFeedback() {
    if (_disposed) return;
    _notifySpanFeedbackAbort();
  }

  /// Sets or clears the active [ChatSpanFeedback].
  void setSpanFeedback(ChatSpanFeedback? feedback) {
    if (_disposed || identical(_spanFeedback, feedback)) return;
    _spanFeedback = feedback;
    _notifySpanFeedback(feedback);
  }

  bool _hasEstablishedTextRange = false;
  bool _pendingWordSelect = false;
  bool _isDisarming = false;

  void _onTextRangeChanged() {
    if (_disposed || _isDisarming) return;
    if (_pendingWordSelect) return;

    switch (_text.range) {
      case final sel? when !sel.isCollapsed:
        final docId = sel.base.documentId;
        final extentId = sel.extent.documentId;
        // Character ranges stay one message — drop cross-document commits.
        if (docId != extentId) {
          clearTextSelection();
          return;
        }
        if (docId is int) {
          if (!_text.isActive || _text.subjectId != docId) {
            if (!_adoptTextSubject(docId)) {
              return;
            }
          }
          _hasEstablishedTextRange = true;
        }
      case _ when _text.isActive && _hasEstablishedTextRange:
        clearTextSelection();
        return;
      case _:
        break;
    }
    _notify();
  }

  /// Adopts a scope-created range as the active **text selection subject**.
  ///
  /// Preserves the markdown range. Applies [selectionPolicy] enter membership
  /// (mobile nest / desktop exclusive clear). Returns `false` when policy or
  /// registration refuses the subject.
  bool _adoptTextSubject(int messageId) {
    if (_disposed) return false;
    if (!selectionPolicy.allowsTextEntryWithoutMessageSelection &&
        !isSelected(messageId)) {
      return false;
    }
    if (!_text.adopt(messageId)) return false;
    selectionPolicy.applyEnterMembership(
      replaceSelectedIds: replaceSelectedIds,
      clearMessageSelection: _clearMessageIds,
      messageId: messageId,
    );
    return true;
  }

  /// Optional maximum size of [selectedIds]. `null` (the default) means
  /// unlimited.
  ///
  /// A select span does not grow past this size. Unselect spans ignore it
  /// and may shrink the set while it is at the cap.
  int? selectionCap;

  /// Whether [count] has reached [selectionCap]. Always `false` when the
  /// cap is `null`.
  bool get isAtSelectionCap {
    final cap = selectionCap;
    return cap != null && _selectedIds.length >= cap;
  }

  /// Bumps whenever an add is refused because the set is already at
  /// [selectionCap]. The selected set does not change, so [addListener]
  /// on this controller does not fire — listen here to shake chrome or
  /// play an error haptic.
  ValueListenable<int> get capHits => _capHits;

  bool _capHitScheduled = false;

  /// Records a refused add at [selectionCap]. The viewport calls this
  /// when a select span cannot grow; hosts normally listen to [capHits]
  /// instead of calling this themselves.
  void notifyCapHit() {
    void bump() {
      if (_disposed) return;
      _capHits.value++;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_capHitScheduled) return;
      _capHitScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _capHitScheduled = false;
        bump();
      });
      return;
    }
    bump();
  }

  /// Whether a long-press on [messageId] at [globalOffset] would route into
  /// text selection under [selectionPolicy].
  ///
  /// Mobile: requires [messageId] to be already message-selected and the
  /// point to hit that message’s body (mounted surface, or reported paint
  /// bounds when the surface is unmounted for a non-subject). When text is
  /// already active on another message, yielding applies only to the current
  /// subject; retarget onto another selected body is handled by the viewport
  /// long-press calling [enterTextSelection].
  ///
  /// The viewport uses this on pointer-down to **yield** its long-press
  /// recognizer so the per-body markdown scope owns the continuous press
  /// (ADR 015). It is not a one-shot enter-text API.
  @internal
  bool shouldRouteLongPressToText(int messageId, Offset globalOffset) {
    if (_disposed) return false;
    if (!selectionPolicy.routesLongPressToTextSelection) return false;
    if (!isSelected(messageId)) return false;
    // While text is live, only the subject mounts a surface / enabled scope.
    // Do not yield for siblings — the viewport keeps the long-press to retarget
    // or run an unselect span (padding).
    if (_text.isActive && _text.subjectId != messageId) return false;
    return _text.containsGlobal(messageId, globalOffset);
  }

  /// Whether a long-press on [messageId] at [globalOffset] routes to text.
  ///
  /// Returns the same predicate as [shouldRouteLongPressToText]. Does **not**
  /// one-shot [enterTextSelection] — continuous entry is owned by the per-body
  /// markdown scope after the viewport yields (ADR 015). Prefer
  /// [enterTextSelection] / [armTextSelection] for programmatic hosts and
  /// tests.
  ///
  /// Viewport selection pointer only (legacy name retained for Seam S).
  @internal
  bool routeLongPressToTextSelection(int messageId, Offset globalOffset) =>
      shouldRouteLongPressToText(messageId, globalOffset);

  /// Host predicate: per-id membership and chrome grants.
  /// `null` (the default) is [ChatSelectionAllowed.full] for every
  /// present message. A non-selectable id is never a span hit and is omitted
  /// from the selection span. Chrome wrap follows
  /// [ChatSelectionAllowed.showsChrome].
  ///
  /// Assigning a new function (or `null`) re-filters [selectedIds] and
  /// notifies [addSelectionAllowedListener]. Prefer a new closure (or
  /// [reapplySelectionAllowed]) when closed-over host state changes.
  ChatSelectionAllowed Function(int messageId)? get selectionAllowed =>
      _selectionAllowed;
  set selectionAllowed(ChatSelectionAllowed Function(int messageId)? value) {
    if (identical(_selectionAllowed, value)) return;
    _selectionAllowed = value;
    reapplySelectionAllowed();
  }

  ChatSelectionAllowed Function(int messageId)? _selectionAllowed;

  /// Resolved [ChatSelectionAllowed] for [messageId].
  /// [ChatSelectionAllowed.full] when [selectionAllowed] is null.
  ChatSelectionAllowed isSelectionAllowed(int messageId) =>
      _selectionAllowed?.call(messageId) ?? ChatSelectionAllowed.full;

  /// Whether [messageId] may join the selected set.
  bool isSelectable(int messageId) =>
      isSelectionAllowed(messageId).isSelectable;

  /// Re-runs [selectionAllowed] against [selectedIds] and notifies
  /// [addSelectionAllowedListener] without requiring a new function
  /// identity.
  ///
  /// Use when the predicate closes over mutable host state that changed
  /// in place and the host did not reassign [selectionAllowed].
  void reapplySelectionAllowed() {
    _notifySelectionAllowed();
    final next = _selectedIds.where(isSelectable).toSet();
    if (next.length == _selectedIds.length && _selectedIds.containsAll(next)) {
      return;
    }
    _selectedIds
      ..clear()
      ..addAll(next);
    _onMembershipChanged();
    _notify();
  }

  /// Registers [listener] for [selectionAllowed] changes (assign or
  /// [reapplySelectionAllowed]). Dedup-on-add; snapshot dispatch.
  ///
  /// The selected-set [Listenable] does **not** fire when [selectedIds] is
  /// unchanged — listen here for chrome-wrap invalidation.
  void addSelectionAllowedListener(VoidCallback listener) {
    if (_selectionAllowedListeners.contains(listener)) return;
    _selectionAllowedListeners.add(listener);
  }

  /// Removes a listener registered with [addSelectionAllowedListener].
  void removeSelectionAllowedListener(VoidCallback listener) =>
      _selectionAllowedListeners.remove(listener);

  void _notifySelectionAllowed() {
    for (final cb in _selectionAllowedListeners.toList(growable: false)) {
      cb();
    }
  }

  // --- Listeners ---

  /// Plain `List` so the field's runtime type stays stable across hot-reload.
  /// `addListener` dedups explicitly so a double-registration with the same
  /// closure is a no-op — otherwise the symmetric `removeListener` only
  /// strips one of multiple registrations and the listener silently keeps
  /// firing for the rest of the controller's lifetime.
  final _listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  bool _notifyScheduled = false;

  void _notify() {
    // Span auto-scroll applies from performLayout. Listeners (composer,
    // chrome) call setState — illegal during persistentCallbacks. Same
    // trampoline as ChatScrollController.isAtTail.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (_disposed) return;
        _notifyNow();
      });
      return;
    }
    _notifyNow();
  }

  void _notifyNow() {
    // Iterate a snapshot: a listener may add/remove listeners while reacting
    // (e.g. a message widget unmounting during the resulting rebuild).
    for (final cb in _listeners.toList(growable: false)) {
      cb();
    }
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// Drop all listeners. Call from the owning widget's `dispose`. Idempotent
  /// — safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dragSelectedIds = null;
    _hasEstablishedTextRange = false;
    _pendingWordSelect = false;
    _text.markdownSelection.removeListener(_onTextRangeChanged);
    _listeners.clear();
    _selectionAllowedListeners.clear();
    _copySuccessListeners.clear();
    _linkTapListeners.clear();
    _linkLongPressListeners.clear();
    _codeTapListeners.clear();
    _spanFeedbackListeners.clear();
    _spanFeedbackTriggerListeners.clear();
    _spanFeedbackReleaseListeners.clear();
    _spanFeedbackAbortListeners.clear();
    _spanFeedback = null;
    _capHits.dispose();
    _text.dispose();
    // Drop the set: a stale reference held by a consumer (e.g. a toolbar
    // queueing an undo) must not silently match unrelated ids in a fresh
    // conversation that happens to reuse the same numeric range.
    _selectedIds.clear();
  }
}
