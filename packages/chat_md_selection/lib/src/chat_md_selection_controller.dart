import 'package:chat_md_selection/src/chat_md_selection_policy.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Coordinates [ChatSelectionController] message membership with markdown
/// character ranges for one **text selection subject**, under a
/// [ChatMdSelectionPolicy].
///
/// Entry, nesting, span-yield claim, gesture arming, and Copy-success effects
/// come from [policy]. [armsMarkdownGestures] is the SoT for
/// [ChatMdSelectionScope.enabled]. Hosts MUST NOT replace [policy] while this
/// controller is alive.
final class ChatMdSelectionController implements Listenable {
  /// Creates a controller bound to [messageSelection].
  ///
  /// When [markdownSelection] is omitted, a [MarkdownSelectionController] is
  /// created and disposed with this controller.
  ChatMdSelectionController({
    required this.messageSelection,
    ChatMdSelectionPolicy? policy,
    this.onCopySuccess,
    MarkdownSelectionController? markdownSelection,
  }) : policy = policy ?? ChatMdSelectionPolicy.forPlatform(),
       _disposeMarkdown = switch (markdownSelection) {
         null => true,
         _ => false,
       },
       markdownSelection = markdownSelection ?? MarkdownSelectionController() {
    // Tear-off stored for [identical] ownership check in [dispose].
    _$spanYieldPredicate = shouldSpanYield;
    messageSelection
      ..spanYield = _$spanYieldPredicate
      ..addSpanYieldedListener(_onSpanYielded)
      ..addListener(_onMessageSelectionChanged);
    this.markdownSelection.addListener(_onMarkdownSelectionChanged);
  }

  /// Active **selection policy** (entry, nesting, yield claim, Copy).
  final ChatMdSelectionPolicy policy;

  /// Optional host hook invoked after a successful Copy clipboard write.
  ///
  /// Receives the copied plain text. Prefer [addCopySuccessListener] when
  /// multiple observers need the same event.
  final ValueChanged<String>? onCopySuccess;

  /// Message-selection controller supplied at construction.
  final ChatSelectionController messageSelection;

  /// Markdown selection SoT used by [ChatMdSelectionScope] / [ChatMdBody].
  final MarkdownSelectionController markdownSelection;

  final bool _disposeMarkdown;

  late final bool Function(int messageId, Offset globalOffset)
  _$spanYieldPredicate;

  final Map<int, _BodyEntry> _bodies = <int, _BodyEntry>{};
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final List<ValueChanged<String>> _$copySuccessListeners =
      <ValueChanged<String>>[];

  int? _$subjectId;
  var _$active = false;
  var _$disposed = false;
  var _$pruningRegistry = false;
  var _$pendingWordSelect = false;
  var _$hadTextRange = false;

  /// Whether character-range text selection is active for [textSelectionSubject].
  bool get isTextSelectionActive => _$active;

  /// Message ID of the active text selection, or null when inactive.
  int? get textSelectionSubject => _$subjectId;

  /// Whether this controller has been [dispose]d.
  bool get isDisposed => _$disposed;

  /// Whether [ChatMdSelectionScope] should enable markdown selection gestures.
  ///
  /// True while text selection is active, or under a policy that allows direct
  /// text entry when message membership is empty (desktop/web). Mobile stays
  /// inert until programmatic / span-yield entry. Hosts MUST NOT invent a
  /// parallel enable flag — this is the single arming SoT for the scope.
  bool get armsMarkdownGestures {
    if (_$disposed) return false;
    if (_$active) return true;
    return policy.allowsTextEntryWithoutMessageSelection &&
        messageSelection.selectedIds.isEmpty;
  }

  /// Whether [messageId] is the armed text-selection subject in the document
  /// registry.
  ///
  /// True only while text selection is active and [messageId] is the subject.
  /// Selected non-subject bodies may mount a surface for yield hit-testing
  /// while inactive ([exposesSelectionSurface]); they MUST NOT stay in the
  /// armed document registry.
  bool isDocumentArmed(int messageId) => _$active && _$subjectId == messageId;

  /// Whether [ChatMdBody] should mount a markdown selection surface for
  /// [messageId].
  ///
  /// While text-active: only the subject (blocks heal-registration from
  /// opening cross-message ranges). While inactive under direct-entry policy
  /// (desktop): every registered body only when message membership is empty,
  /// so drag / double-click can start. While inactive under nested policy
  /// (mobile): selected registered bodies for span-yield hit-testing.
  /// Gestures stay gated by [armsMarkdownGestures] /
  /// [ChatMdSelectionScope.enabled].
  bool exposesSelectionSurface(int messageId) {
    if (_$disposed) return false;
    if (!_bodies.containsKey(messageId)) return false;
    if (_$active) return _$subjectId == messageId;
    if (policy.allowsTextEntryWithoutMessageSelection) {
      return messageSelection.selectedIds.isEmpty;
    }
    if (!messageSelection.isSelected(messageId)) return false;
    return true;
  }

  /// Registered model for [messageId], or null when never [putBody]'d.
  Markdown? bodyOf(int messageId) => _bodies[messageId]?.model;

  /// Inserts or updates the markdown body for [messageId].
  ///
  /// [order] is the reading-order key when the document is armed.
  void putBody(int messageId, Markdown model, {int? order}) {
    if (_$disposed) return;
    final existing = _bodies[messageId];
    final assigned = order ?? existing?.order ?? _bodies.length;
    if (existing case final e?
        when identical(e.model, model) && e.order == assigned) {
      return;
    }
    _bodies[messageId] = _BodyEntry(model, assigned);
    if (_$active && _$subjectId == messageId) {
      _syncArmedDocument();
    }
    _notify();
  }

  /// Removes a previously registered body.
  ///
  /// When [messageId] is the active subject, clears text selection first.
  void removeBody(int messageId) {
    if (_$disposed) return;
    if (!_bodies.containsKey(messageId)) return;
    if (_$active && _$subjectId == messageId) {
      clearTextSelection();
    }
    _bodies.remove(messageId);
    _notify();
  }

  /// Pure span-yield predicate: selected [messageId] whose selectable body
  /// text contains [globalOffset], when [policy] claims yield for text entry.
  ///
  /// MUST NOT start text selection or mutate membership. Wired to
  /// [ChatSelectionController.spanYield] at construction. Returns `false`
  /// when disposed, [policy] does not claim yield, [messageId] is not
  /// selected, no body is registered, or the point misses that message’s
  /// mounted selectable text (padding / chrome / another surface).
  bool shouldSpanYield(int messageId, Offset globalOffset) {
    if (_$disposed) return false;
    if (!policy.claimsSpanYieldForTextEntry) return false;
    if (!messageSelection.isSelected(messageId)) return false;
    if (!_bodies.containsKey(messageId)) return false;
    final hit = markdownSelection.positionForGlobal(
      globalOffset,
      requireContainment: true,
    );
    return switch (hit) {
      final p? when p.documentId == messageId => true,
      _ => false,
    };
  }

  /// Enters text selection for [messageId] under [policy].
  ///
  /// Mobile: requires an already-selected [messageId], collapses membership
  /// to that id, arms only that document. Desktop: allows entry without prior
  /// membership and clears the selected set (exclusive). With [globalOffset],
  /// selects the word at that point after the next frame (surface attach).
  /// Without [globalOffset], selects the entire subject body immediately.
  ///
  /// Returns `false` when disposed, entry is blocked by [policy] / missing
  /// body, or (without [globalOffset]) select-all produced no range.
  /// Pre-arm failures leave prior text-selection state unchanged. With
  /// [globalOffset], a synchronous `true` means the subject is armed; the
  /// word range lands next frame (a miss clears the markdown range only).
  bool enterTextSelection(int messageId, {Offset? globalOffset}) {
    if (_$disposed) return false;
    if (!policy.allowsTextEntryWithoutMessageSelection &&
        !messageSelection.isSelected(messageId)) {
      return false;
    }
    final entry = _bodies[messageId];
    if (entry == null) return false;

    // Arm before membership mutation so desktop clear does not look like
    // "subject dropped while nested" to [_onMessageSelectionChanged].
    _$subjectId = messageId;
    _$active = true;
    _$hadTextRange = false;
    policy.applyEnterMembership(messageSelection, messageId);
    _syncArmedDocument();
    _notify();
    // Heal from a still-mounted outgoing surface can re-register a neighbor
    // before ChatMdBody clears its documentId on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_$disposed || !_$active || _$subjectId != messageId) return;
      _syncArmedDocument();
    });

    return switch (globalOffset) {
      null => _selectAllSubject(),
      final point => _scheduleWordAtGlobal(messageId, point),
    };
  }

  bool _selectAllSubject() {
    markdownSelection.selectAll();
    return switch (markdownSelection.selection) {
      final sel? when !sel.isCollapsed => true,
      _ => false,
    };
  }

  bool _scheduleWordAtGlobal(int messageId, Offset globalOffset) {
    // Word selection needs a mounted surface; arming notifies bodies first.
    // Pending flag blocks dismiss-sync while the range is still null.
    _$pendingWordSelect = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _$pendingWordSelect = false;
      if (_$disposed || !_$active || _$subjectId != messageId) return;
      final sel = markdownSelection.selectWordAtGlobal(globalOffset);
      if (sel == null) {
        markdownSelection.clear();
      }
      _notify();
    });
    return true;
  }

  /// Clears markdown text selection and disarms every document.
  ///
  /// Leaves [messageSelection] unchanged. Selected bodies may keep surfaces
  /// for a later yield hit-test. This is the dismiss-text exit (tap / Esc /
  /// equivalent).
  void clearTextSelection() {
    if (_$disposed) return;
    if (!_$active && markdownSelection.selection == null) {
      _pruneRegistryIfInactive();
      return;
    }
    _$active = false;
    _$subjectId = null;
    _$hadTextRange = false;
    _$pendingWordSelect = false;
    markdownSelection
      ..clear()
      ..setDocuments(const <MarkdownDocumentRef>[]);
    _notify();
  }

  /// Copies the active plain-text range, then applies [policy] Copy-success
  /// effects and notifies Copy-success observers.
  ///
  /// Places [MarkdownSelectionController.getText] on the clipboard when
  /// non-empty, then [ChatMdSelectionPolicy.applyCopySuccess]. Returns
  /// `false` when disposed, text selection is inactive, or there is no
  /// non-empty range (state unchanged; no Copy-success notify).
  Future<bool> copyTextSelection() async {
    if (_$disposed || !_$active) return false;
    final text = markdownSelection.getText();
    if (text.isEmpty) return false;
    await Clipboard.setData(ClipboardData(text: text));
    policy.applyCopySuccess(
      clearTextSelection: clearTextSelection,
      clearMessageSelection: messageSelection.clear,
    );
    _notifyCopySuccess(text);
    return true;
  }

  /// Registers [listener] for successful Copy (clipboard write completed).
  ///
  /// Dedup-on-add; snapshot dispatch. Payload is the copied plain text.
  /// Silent when [copyTextSelection] returns `false`.
  void addCopySuccessListener(ValueChanged<String> listener) {
    if (_$disposed) return;
    if (_$copySuccessListeners.contains(listener)) return;
    _$copySuccessListeners.add(listener);
  }

  /// Removes a listener registered with [addCopySuccessListener].
  void removeCopySuccessListener(ValueChanged<String> listener) {
    _$copySuccessListeners.remove(listener);
  }

  void _notifyCopySuccess(String text) {
    onCopySuccess?.call(text);
    for (final cb in List<ValueChanged<String>>.of(
      _$copySuccessListeners,
      growable: false,
    )) {
      cb(text);
    }
  }

  void _onSpanYielded(int messageId, Offset globalOffset) {
    enterTextSelection(messageId, globalOffset: globalOffset);
  }

  void _onMessageSelectionChanged() {
    if (_$disposed) return;
    if (_$active) {
      final subject = _$subjectId;
      if (policy.nestsTextSubjectInMessageSelection) {
        if (subject == null || !messageSelection.isSelected(subject)) {
          clearTextSelection();
          return;
        }
        _syncArmedDocument();
      } else if (messageSelection.selectedIds.isNotEmpty) {
        // Exclusive: any message membership dismisses text.
        clearTextSelection();
        return;
      } else {
        _syncArmedDocument();
      }
    } else {
      _pruneRegistryIfInactive();
    }
    // Selected set drives surface exposure on [ChatMdBody].
    _notify();
  }

  void _onMarkdownSelectionChanged() {
    if (_$disposed || _$pruningRegistry) return;
    if (_$active) {
      // Tap/Esc dismiss clears a previously established range. A pending
      // word-at-global (range still null) and a miss (never had a range) MUST
      // NOT leave text-active mode via this path.
      if (_$pendingWordSelect) return;
      switch (markdownSelection.selection) {
        case final sel? when !sel.isCollapsed:
          _$hadTextRange = true;
        case _ when _$hadTextRange:
          clearTextSelection();
        case _:
          break;
      }
      return;
    }
    // Desktop/web: a gesture-created range while gestures are armed becomes
    // exclusive text selection for that document.
    if (armsMarkdownGestures) {
      switch (markdownSelection.selection) {
        case final sel? when !sel.isCollapsed:
          final id = sel.base.documentId;
          if (id case final int messageId when _bodies.containsKey(messageId)) {
            _adoptGestureTextSelection(messageId);
          }
        case _:
          break;
      }
      return;
    }
    _pruneRegistryIfInactive();
  }

  /// Arms exclusive text mode from a markdown gesture range on [messageId].
  ///
  /// Collapses the document registry to the subject so heal-registered
  /// neighbors cannot keep a cross-message character range. When the live
  /// extent lies on another document, collapses onto [sel.base] before
  /// [setDocuments] so validation does not wipe the selection entirely.
  void _adoptGestureTextSelection(int messageId) {
    // Mark active first so a selection write below re-enters the active path,
    // not another adopt.
    _$subjectId = messageId;
    _$active = true;
    policy.applyEnterMembership(messageSelection, messageId);

    final sel = markdownSelection.selection;
    if (sel != null && sel.extent.documentId != messageId) {
      // Base is always the adopt subject; drop the foreign extent.
      markdownSelection.selection = MarkdownSelection(
        base: sel.base,
        extent: sel.base,
      );
      _$hadTextRange = false;
    } else {
      _$hadTextRange = switch (sel) {
        final s? when !s.isCollapsed => true,
        _ => false,
      };
    }
    _syncArmedDocument();
    _notify();
    // Scope rebuild can update still-mounted non-subject surfaces before their
    // ChatMdBody turns documentId off; heal putDocument would re-open neighbors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_$disposed || !_$active || _$subjectId != messageId) return;
      _syncArmedDocument();
    });
  }

  /// Drops heal-registered documents while text selection is inactive so
  /// selected surfaces can hit-test without arming character ranges.
  ///
  /// Skipped while [armsMarkdownGestures] needs heal-registered documents for
  /// direct desktop/web entry.
  void _pruneRegistryIfInactive() {
    if (_$disposed || _$active) return;
    if (armsMarkdownGestures) return;
    if (markdownSelection.documentCount == 0 &&
        markdownSelection.selection == null) {
      return;
    }
    _$pruningRegistry = true;
    try {
      markdownSelection
        ..clear()
        ..setDocuments(const <MarkdownDocumentRef>[]);
    } finally {
      _$pruningRegistry = false;
    }
  }

  void _syncArmedDocument() {
    final id = _$subjectId;
    if (!_$active || id == null) {
      markdownSelection.setDocuments(const <MarkdownDocumentRef>[]);
      return;
    }
    final entry = _bodies[id];
    if (entry == null) {
      markdownSelection.setDocuments(const <MarkdownDocumentRef>[]);
      return;
    }
    markdownSelection.setDocuments(<MarkdownDocumentRef>[
      MarkdownDocumentRef(id: id, model: entry.model, order: entry.order),
    ]);
  }

  @override
  void addListener(VoidCallback listener) {
    if (_$disposed) return;
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final cb in List<VoidCallback>.of(_listeners, growable: false)) {
      cb();
    }
  }

  /// Clears listeners and, when created here, disposes [markdownSelection].
  ///
  /// Clears [ChatSelectionController.spanYield] when it still points at this
  /// controller’s predicate.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    messageSelection.removeListener(_onMessageSelectionChanged);
    messageSelection.removeSpanYieldedListener(_onSpanYielded);
    if (identical(messageSelection.spanYield, _$spanYieldPredicate)) {
      messageSelection.spanYield = null;
    }
    markdownSelection.removeListener(_onMarkdownSelectionChanged);
    _$active = false;
    _$subjectId = null;
    _$hadTextRange = false;
    _$pendingWordSelect = false;
    _bodies.clear();
    _listeners.clear();
    _$copySuccessListeners.clear();
    markdownSelection.clear();
    markdownSelection.setDocuments(const <MarkdownDocumentRef>[]);
    if (_disposeMarkdown) {
      markdownSelection.dispose();
    }
  }
}

@immutable
final class _BodyEntry {
  const _BodyEntry(this.model, this.order);
  final Markdown model;
  final int order;
}
