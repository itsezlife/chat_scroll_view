import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Coordinates [ChatSelectionController] message membership with markdown
/// character ranges for one **text selection subject**.
///
/// Markdown selection stays inert until [enterTextSelection]. Entry collapses
/// [messageSelection] to `{subject}` and arms only that document. Dropping the
/// subject from message selection clears text selection. Implements
/// [Listenable] for arming / clear rebuilds.
final class ChatMdSelectionController implements Listenable {
  /// Creates a controller bound to [messageSelection].
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
    messageSelection.addListener(_onMessageSelectionChanged);
  }

  /// Message-selection controller supplied at construction.
  final ChatSelectionController messageSelection;

  /// Markdown selection SoT used by [ChatMdSelectionScope] / [ChatMdBody].
  final MarkdownSelectionController markdownSelection;

  final bool _disposeMarkdown;

  final Map<int, _BodyEntry> _bodies = <int, _BodyEntry>{};
  final List<VoidCallback> _listeners = <VoidCallback>[];

  int? _$subjectId;
  var _$active = false;
  var _$disposed = false;

  /// Whether character-range text selection is active for [textSelectionSubject].
  ///
  /// Also drives [ChatMdSelectionScope] gesture enablement.
  bool get isTextSelectionActive => _$active;

  /// Message ID of the active text selection, or null when inactive.
  int? get textSelectionSubject => _$subjectId;

  /// Whether this controller has been [dispose]d.
  bool get isDisposed => _$disposed;

  /// Whether [messageId] exposes a selectable markdown `documentId`.
  ///
  /// True only while text selection is active and [messageId] is the subject.
  /// Non-subject bodies MUST omit a document id so heal-registration cannot
  /// open cross-message character ranges.
  bool isDocumentArmed(int messageId) =>
      _$active && _$subjectId == messageId;

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
  /// Leaves [messageSelection] unchanged.
  void clearTextSelection() {
    if (_$disposed) return;
    if (!_$active && markdownSelection.selection == null) return;
    _$active = false;
    _$subjectId = null;
    markdownSelection
      ..clear()
      ..setDocuments(const <MarkdownDocumentRef>[]);
    _notify();
  }

  void _onMessageSelectionChanged() {
    if (_$disposed || !_$active) return;
    final subject = _$subjectId;
    if (subject == null || !messageSelection.isSelected(subject)) {
      clearTextSelection();
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
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    messageSelection.removeListener(_onMessageSelectionChanged);
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
