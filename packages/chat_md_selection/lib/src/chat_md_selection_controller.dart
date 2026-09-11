import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Coordinates [ChatSelectionController] message membership with markdown
/// character ranges for one **text selection subject**.
///
/// ## Message-then-text order
///
/// Markdown selection stays inert until [enterTextSelection]. Construction
/// owns [ChatSelectionController.spanYield] and a yield notify listener:
/// [shouldSpanYield] claims only when [messageId] is already selected and
/// [globalOffset] hits that message’s selectable body text; the notify then
/// calls [enterTextSelection] at that point. First long-press on glyphs of an
/// unselected message never yields — message selection / span still wins.
///
/// ## Surfaces vs arming
///
/// While text selection is inactive, selected messages expose a markdown
/// selection surface so yield can hit-test body text. While text selection is
/// active, only the subject exposes a surface. Only the subject is **armed**
/// in the document registry ([isDocumentArmed]); heal-registration from other
/// surfaces is pruned while inactive. Dropping the subject from message
/// selection clears text selection.
final class ChatMdSelectionController implements Listenable {
  /// Creates a controller bound to [messageSelection].
  ///
  /// Wires [ChatSelectionController.spanYield] to [shouldSpanYield] and
  /// listens for claimed yields to enter text selection. Hosts MUST NOT
  /// replace [ChatSelectionController.spanYield] while this controller is
  /// alive; dispose clears the predicate when it still owns it.
  ///
  /// When [markdownSelection] is omitted, a [MarkdownSelectionController] is
  /// created and disposed with this controller.
  ChatMdSelectionController({
    required this.messageSelection,
    MarkdownSelectionController? markdownSelection,
  }) : _disposeMarkdown = switch (markdownSelection) {
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

  /// Message-selection controller supplied at construction.
  final ChatSelectionController messageSelection;

  /// Markdown selection SoT used by [ChatMdSelectionScope] / [ChatMdBody].
  final MarkdownSelectionController markdownSelection;

  final bool _disposeMarkdown;

  late final bool Function(int messageId, Offset globalOffset)
  _$spanYieldPredicate;

  final Map<int, _BodyEntry> _bodies = <int, _BodyEntry>{};
  final List<VoidCallback> _listeners = <VoidCallback>[];

  int? _$subjectId;
  var _$active = false;
  var _$disposed = false;
  var _$pruningRegistry = false;

  /// Whether character-range text selection is active for [textSelectionSubject].
  ///
  /// Also drives [ChatMdSelectionScope] gesture enablement.
  bool get isTextSelectionActive => _$active;

  /// Message ID of the active text selection, or null when inactive.
  int? get textSelectionSubject => _$subjectId;

  /// Whether this controller has been [dispose]d.
  bool get isDisposed => _$disposed;

  /// Whether [messageId] is the armed text-selection subject in the document
  /// registry.
  ///
  /// True only while text selection is active and [messageId] is the subject.
  /// Selected non-subject bodies may mount a surface for yield hit-testing
  /// while inactive ([exposesSelectionSurface]); they MUST NOT stay in the
  /// armed document registry.
  bool isDocumentArmed(int messageId) =>
      _$active && _$subjectId == messageId;

  /// Whether [ChatMdBody] should mount a markdown selection surface for
  /// [messageId].
  ///
  /// While text selection is inactive: every selected registered body, so
  /// yield can hit-test. While active: only the subject, so heal-registration
  /// cannot open cross-message character ranges. Character-range gestures
  /// stay gated by [isDocumentArmed] / [ChatMdSelectionScope.enabled].
  bool exposesSelectionSurface(int messageId) {
    if (_$disposed) return false;
    if (!_bodies.containsKey(messageId)) return false;
    if (!messageSelection.isSelected(messageId)) return false;
    if (_$active) return _$subjectId == messageId;
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
  /// text contains [globalOffset].
  ///
  /// MUST NOT start text selection or mutate membership. Wired to
  /// [ChatSelectionController.spanYield] at construction. Returns `false`
  /// when disposed, [messageId] is not selected, no body is registered, or
  /// the point misses that message’s mounted selectable text (padding /
  /// chrome / another surface).
  bool shouldSpanYield(int messageId, Offset globalOffset) {
    if (_$disposed) return false;
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

  /// Enters text selection for an already-selected [messageId].
  ///
  /// Collapses [messageSelection] to `{messageId}`, arms only that document,
  /// and enables markdown selection chrome. With [globalOffset], selects the
  /// word at that point after the next frame (surface attach). Without
  /// [globalOffset], selects the entire subject body immediately.
  ///
  /// Returns `false` when disposed, [messageId] is not selected, no body is
  /// registered, or (without [globalOffset]) select-all produced no range.
  /// Pre-arm failures leave prior text-selection state unchanged. With
  /// [globalOffset], a synchronous `true` means the subject is armed; the
  /// word range lands next frame (a miss clears the markdown range only).
  bool enterTextSelection(int messageId, {Offset? globalOffset}) {
    if (_$disposed) return false;
    if (!messageSelection.isSelected(messageId)) return false;
    final entry = _bodies[messageId];
    if (entry == null) return false;

    messageSelection.replaceSelectedIds(<int>{messageId});
    _$subjectId = messageId;
    _$active = true;
    _syncArmedDocument();
    _notify();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
  /// for a later yield hit-test.
  void clearTextSelection() {
    if (_$disposed) return;
    if (!_$active && markdownSelection.selection == null) {
      _pruneRegistryIfInactive();
      return;
    }
    _$active = false;
    _$subjectId = null;
    markdownSelection
      ..clear()
      ..setDocuments(const <MarkdownDocumentRef>[]);
    _notify();
  }

  void _onSpanYielded(int messageId, Offset globalOffset) {
    enterTextSelection(messageId, globalOffset: globalOffset);
  }

  void _onMessageSelectionChanged() {
    if (_$disposed) return;
    if (_$active) {
      final subject = _$subjectId;
      if (subject == null || !messageSelection.isSelected(subject)) {
        clearTextSelection();
        return;
      }
      _syncArmedDocument();
    } else {
      _pruneRegistryIfInactive();
    }
    // Selected set drives surface exposure on [ChatMdBody].
    _notify();
  }

  void _onMarkdownSelectionChanged() {
    if (_$disposed || _$pruningRegistry) return;
    if (!_$active) {
      _pruneRegistryIfInactive();
    }
  }

  /// Drops heal-registered documents while text selection is inactive so
  /// selected surfaces can hit-test without arming character ranges.
  void _pruneRegistryIfInactive() {
    if (_$disposed || _$active) return;
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
    _bodies.clear();
    _listeners.clear();
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
