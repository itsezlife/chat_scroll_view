import 'dart:collection';

import 'package:chat_scroll_view/src/chat_scroll/chat_inline_hit.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_non_text_body.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_code_block_painter.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_smooth_contour.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart';

/// Internal **text selection** module owned by the public selection facade.
///
/// Reuses the markdown library’s selection *model* ([MarkdownSelectionController]
/// positions, document registry, [getText]) for one **text selection subject**.
/// Does not wrap the chat list in [MarkdownSelectionScope] — that scope is
/// not the chat gesture authority.
///
/// Hosts MUST NOT construct this type. Drive subject, range, and Copy through
/// the public facade.
@internal
final class ChatTextSelection {
  /// Creates a text module.
  ChatTextSelection({
    MarkdownSelectionController? markdownSelection,
    MarkdownSpoilerController? spoilers,
    ChatSelectionPolicy? policy,
  }) : _disposeMarkdown = markdownSelection == null,
       _disposeSpoilers = spoilers == null,
       // The engine copies markdown by default; the viewport's own text is
       // plain (what the clipboard gets without a [ChatTextCopyWriter], and
       // what a host menu reads as [ChatTextCopy.plainText]). Rich forms read
       // the structured content instead.
       markdownSelection =
           markdownSelection ??
           MarkdownSelectionController(
             formatter: MarkdownSelectionFormatter.plain,
           ),
       spoilers = spoilers ?? MarkdownSpoilerController(),
       policy = policy ?? ChatSelectionPolicy.forPlatform();

  /// Markdown selection model (positions, documents, copy formatting).
  final MarkdownSelectionController markdownSelection;

  /// Which messages have their spoilers revealed, keyed by message id.
  ///
  /// Beside [markdownSelection], not inside it: one answers where a range
  /// sits over a registry of bodies, the other holds one bit per message, and
  /// the two change for different reasons.
  final MarkdownSpoilerController spoilers;

  /// Selection policy governing cross-platform code block and gesture arbitration.
  final ChatSelectionPolicy policy;

  final bool _disposeMarkdown;
  final bool _disposeSpoilers;

  final Map<int, _BodyEntry> _bodies = <int, _BodyEntry>{};

  /// Bodies that paint no text (`ChatNonTextBody`), per message, in mount
  /// order: the last is the one a query asks.
  final Map<int, LinkedHashMap<Object, ChatNonTextBody>> _nonTextBodies =
      <int, LinkedHashMap<Object, ChatNonTextBody>>{};

  /// Mounted body paint boxes — resolved to global rects at hit time so
  /// scroll does not stale a cached [Rect].
  final Map<int, RenderBox> _bodyPaintBoxes = <int, RenderBox>{};

  /// Mounted message-surface (bubble) boxes — same live-resolve contract.
  final Map<int, RenderBox> _messageSurfaceBoxes = <int, RenderBox>{};

  /// Outline reported with a [_messageSurfaceBoxes] entry; absent when the
  /// host reported none.
  final Map<int, ShapeBorder> _messageSurfaceShapes = <int, ShapeBorder>{};

  int? _subjectId;
  var _active = false;
  var _disposed = false;

  /// Whether character-range text selection is active for [subjectId].
  bool get isActive => _active;

  /// Message ID of the active text selection, or null when inactive.
  int? get subjectId => _subjectId;

  /// Character range on the markdown model, or null when none.
  MarkdownSelection? get range => markdownSelection.selection;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Registered model for [messageId], or null when never [putBody]'d.
  ///
  /// With several concurrent registered owners for the same message, this is
  /// the last-registered owner’s model among those still mounted.
  Markdown? bodyOf(int messageId) => _bodies[messageId]?.model;

  /// Whether [messageId] has at least one registered markdown body owner.
  bool hasBody(int messageId) => _bodies.containsKey(messageId);

  /// Whether [messageId] is currently the armed text-selection subject.
  bool isDocumentArmed(int messageId) => _active && _subjectId == messageId;

  /// Returns the mounted [MarkdownSelectionSurface] for [messageId], if any.
  MarkdownSelectionSurface? surfaceFor(int messageId) {
    if (_disposed) return null;
    for (final s in markdownSelection.mountedSurfaces) {
      if (s.documentId == messageId) return s;
    }
    return null;
  }

  /// Whether [globalOffset] hits the registered body of [messageId]
  /// (document bounds — padding and empty gutter included).
  ///
  /// Prefer the mounted selection surface. When the surface is unmounted
  /// (subject-only mounts while text is live), fall back to the body
  /// [RenderBox] reported by the body widget so retarget / padding
  /// arbitration still works for message-selected siblings.
  ///
  /// Glyph-tight hit-testing for I-beam / links is separate
  /// (`hitsSelectableGlyphs` / [resolveInlineHit]). This is the text-body
  /// surface for gesture routing — not the message-menu bubble surface
  /// ([containsMessageSurface]).
  bool containsGlobal(int messageId, Offset globalOffset) {
    if (_disposed) return false;
    if (!_bodies.containsKey(messageId)) return false;
    final surface = surfaceFor(messageId);
    if (surface != null) {
      final bounds = surface.globalBounds;
      return !bounds.isEmpty && bounds.contains(globalOffset);
    }
    final reported = _liveGlobalBounds(
      _bodyPaintBoxes[messageId],
      _bodyPaintBoxes,
    );
    return reported != null && reported.contains(globalOffset);
  }

  /// Whether [globalOffset] hits the host-reported **message surface**
  /// (painted bubble / chrome), used for **message menu point state**.
  ///
  /// Uses the mounted [RenderBox] at hit time (scroll-safe). Falls back to
  /// [containsGlobal] when no surface box is registered so text-only hosts
  /// still get Inside on the body.
  bool containsMessageSurface(int messageId, Offset globalOffset) {
    if (_disposed) return false;
    final surface = _liveGlobalBounds(
      _messageSurfaceBoxes[messageId],
      _messageSurfaceBoxes,
    );
    if (surface != null) {
      return surface.contains(globalOffset);
    }
    if (_nonTextBodies[messageId]?.values.last.globalBounds case final bounds?
        when bounds.contains(globalOffset)) {
      return true;
    }
    return containsGlobal(messageId, globalOffset);
  }

  /// Live global rect and reported outline of the **message surface** of
  /// [messageId], or null when no mounted, sized surface box is registered.
  ///
  /// Resolves [RenderBox.localToGlobal] at call time (scroll-safe). `shape`
  /// is null when the host reported the surface without one. Unlike
  /// [containsMessageSurface], never falls back to the text body.
  ({Rect rect, ShapeBorder? shape})? messageSurfaceGlobal(int messageId) {
    if (_disposed) return null;
    final rect = _liveGlobalBounds(
      _messageSurfaceBoxes[messageId],
      _messageSurfaceBoxes,
    );
    if (rect == null) {
      _messageSurfaceShapes.remove(messageId);
      return null;
    }
    return (rect: rect, shape: _messageSurfaceShapes[messageId]);
  }

  /// Current global paint rect for a registered [box], or null when the box
  /// is missing, detached, or unsized (and drops the stale [owner] entry).
  Rect? _liveGlobalBounds(RenderBox? box, Map<int, RenderBox> owner) {
    if (box == null) return null;
    if (!box.attached || !box.hasSize) {
      owner.removeWhere((_, b) => identical(b, box));
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Records the body widget's [RenderBox] for [containsGlobal] fallback.
  ///
  /// Pass `null` on dispose / unmount. Hit-tests resolve
  /// [RenderBox.localToGlobal] at query time — do not cache a global [Rect]
  /// across scroll. Silent after [dispose].
  void reportBodyPaintBounds(int messageId, RenderBox? box) {
    if (_disposed) return;
    if (box == null || !box.hasSize) {
      _bodyPaintBoxes.remove(messageId);
      return;
    }
    _bodyPaintBoxes[messageId] = box;
  }

  /// Records the message surface (bubble) [RenderBox] for menu Inside/Outside,
  /// with the optional [shape] that outlines it inside the box.
  ///
  /// Pass `null` on dispose / unmount; that also drops the shape. Hit-tests
  /// resolve live global geometry at query time so scroll without rebuild
  /// stays correct. Silent after [dispose].
  void reportMessageSurfaceBounds(
    int messageId,
    RenderBox? box, {
    ShapeBorder? shape,
  }) {
    if (_disposed) return;
    if (box == null || !box.hasSize) {
      _messageSurfaceBoxes.remove(messageId);
      _messageSurfaceShapes.remove(messageId);
      return;
    }
    _messageSurfaceBoxes[messageId] = box;
    switch (shape) {
      case final shape?:
        _messageSurfaceShapes[messageId] = shape;
      case null:
        _messageSurfaceShapes.remove(messageId);
    }
  }

  /// Whether the live text-selection highlight contains [globalOffset] on
  /// [messageId] (glyph/box upon — not merely subject membership).
  bool textSelectionContainsGlobal(int messageId, Offset globalOffset) {
    if (_disposed || !_active || _subjectId != messageId) return false;
    final sel = markdownSelection.selection;
    if (sel == null || sel.isCollapsed) return false;
    for (final rect in markdownSelection.globalSelectionRects()) {
      if (rect.contains(globalOffset)) return true;
    }
    return false;
  }

  /// Resolves whether [globalOffset] hits an inline element (link or code)
  /// in the registered body of [messageId].
  ///
  /// Returns a [ChatInlineHit] if an inline element was hit, or `null` if
  /// the point misses text, is outside [messageId], lands on non-inline
  /// body content (plain text, background, padding), or lands within a fenced
  /// code body (which delegates to text selection).
  ChatInlineHit? resolveInlineHit(int messageId, Offset globalOffset) {
    if (_disposed) return null;
    if (_nonTextBodies[messageId]?.values.last case final body?) {
      return body.inlineHitAt(globalOffset);
    }
    if (!_bodies.containsKey(messageId)) return null;
    final hit = markdownSelection.positionForGlobal(
      globalOffset,
      requireContainment: true,
    );
    if (hit == null || hit.documentId != messageId) return null;

    final model = bodyOf(messageId);
    if (model == null ||
        hit.blockIndex < 0 ||
        hit.blockIndex >= model.blocks.length) {
      return null;
    }
    final block = model.blocks[hit.blockIndex];

    final surface = surfaceFor(messageId);
    final contentLocal = surface != null
        ? globalOffset - surface.globalBounds.topLeft
        : null;

    if (block case MD$Code(:final text, :final language)) {
      // Prefer painter-owned chrome (ChatCodeBlockPainter.isLinkAtLocal), with
      // a dy/box fallback when the surface is clipped shorter than the laid-out
      // block (painter bottom bar sits below the render-box bounds).
      var isChrome = surface != null && surface.isLinkAtGlobal(globalOffset);
      if (!isChrome && surface != null && contentLocal != null) {
        final surfaceWidth = surface.globalBounds.width;
        if (contentLocal.dx >= 0 && contentLocal.dx <= surfaceWidth) {
          final boxes = surface.localBoxesForRange(
            hit.blockIndex,
            0,
            text.length,
          );
          if (boxes.isNotEmpty) {
            final codeTop = boxes.first.top;
            final codeBottom = boxes.last.bottom;
            final inHeader =
                contentLocal.dy >= 0 &&
                contentLocal.dy < (codeTop - ChatCodeBlockPainter.padding);
            final inBottom =
                contentLocal.dy >= (codeBottom + ChatCodeBlockPainter.padding);
            if (inHeader && policy.hasInteractiveCodeHeader) {
              isChrome = true;
            } else if (inBottom &&
                policy.hasBottomCodeCopyBarForLength(text.length)) {
              isChrome = true;
            }
          }
        }
      }
      if (isChrome) {
        // Copy chrome is not a text span — no tap-highlight contour.
        return ChatInlineHit.code(
          messageId: messageId,
          code: text,
          language: language,
        );
      }
      return null;
    }

    // Links / inline code: glyph ink only — not empty max-width gutter.
    if (!markdownSelection.hitsSelectableGlyphs(globalOffset)) {
      return null;
    }

    final spanHit = _findSpanAtOffset(block, hit.offset);
    if (spanHit != null) {
      Path? contourPath;
      if (surface != null) {
        final boxes = surface.localBoxesForRange(
          hit.blockIndex,
          spanHit.start,
          spanHit.end,
        );
        if (boxes.isNotEmpty) {
          contourPath = ChatSmoothContour.buildPath(boxes);
        }
      }
      return _inlineHitForSpan(
        messageId,
        spanHit.span,
        contourPath: contourPath,
        touchOrigin: contentLocal,
      );
    }

    return null;
  }

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
    ChatSelectionPolicy? policy,
    bool isHeader = false,
    bool isBottomBar = false,
  }) {
    if (_disposed) return null;
    final model = bodyOf(messageId);
    if (model == null || blockIndex < 0 || blockIndex >= model.blocks.length) {
      return null;
    }
    final block = model.blocks[blockIndex];
    if (block case MD$Code(:final text, :final language)) {
      if (isHeader) {
        if (policy != null && !policy.hasInteractiveCodeHeader) {
          return null;
        }
        return ChatInlineHit.code(
          messageId: messageId,
          code: text,
          language: language,
        );
      }
      if (isBottomBar) {
        if (policy != null &&
            !policy.hasBottomCodeCopyBarForLength(text.length)) {
          return null;
        }
        return ChatInlineHit.code(
          messageId: messageId,
          code: text,
          language: language,
        );
      }
      return null;
    }
    final spanHit = _findSpanAtOffset(block, offset);
    if (spanHit != null) {
      return _inlineHitForSpan(messageId, spanHit.span);
    }
    return null;
  }

  _SpanHitInfo? _findSpanAtOffset(MD$Block block, int offset) {
    _SpanHitInfo? found;
    _forEachSpan(block, (run) {
      final (:span, :start, :end, :isLast) = run;
      if (offset >= start && (offset < end || (isLast && offset <= end))) {
        found = (span: span, start: start, end: end);
        return true;
      }
      return false;
    });
    return found;
  }

  /// Visits the spans of [block] with their rendered-text offsets, in reading
  /// order, until [visit] returns true. `isLast` marks the span that owns the
  /// offset at its own end (the caret after the last character).
  ///
  /// The offsets are the engine's: a list item's text is followed by one
  /// newline before its children, a table cell by a tab and a row by a
  /// newline. Hit-testing reads them through this one walk.
  void _forEachSpan(MD$Block block, bool Function(_SpanRun run) visit) {
    switch (block) {
      case MD$Paragraph(:final spans) ||
          MD$Heading(:final spans) ||
          MD$Quote(:final spans) ||
          MD$Alert(:final spans):
        var current = 0;
        for (var i = 0; i < spans.length; i++) {
          final end = current + spans[i].text.length;
          final isLast = i == spans.length - 1;
          if (visit((
            span: spans[i],
            start: current,
            end: end,
            isLast: isLast,
          ))) {
            return;
          }
          current = end;
        }
      case MD$List(:final items):
        var current = 0;
        bool walkItem(MD$ListItem item) {
          var itemCurrent = current;
          for (var i = 0; i < item.spans.length; i++) {
            final end = itemCurrent + item.spans[i].text.length;
            final isLast = i == item.spans.length - 1 && item.children.isEmpty;
            if (visit((
              span: item.spans[i],
              start: itemCurrent,
              end: end,
              isLast: isLast,
            ))) {
              return true;
            }
            itemCurrent = end;
          }
          current = itemCurrent + 1; // '\n' separator
          return item.children.any(walkItem);
        }

        items.any(walkItem);
      case MD$Table():
        var current = 0;
        bool walkCells(List<List<MD$Span>> rowCells) {
          for (var i = 0; i < rowCells.length; i++) {
            final cellSpans = rowCells[i];
            var cellCurrent = current;
            for (var j = 0; j < cellSpans.length; j++) {
              final end = cellCurrent + cellSpans[j].text.length;
              final isLast = j == cellSpans.length - 1;
              if (visit((
                span: cellSpans[j],
                start: cellCurrent,
                end: end,
                isLast: isLast,
              ))) {
                return true;
              }
              cellCurrent = end;
            }
            current = cellCurrent + (i < rowCells.length - 1 ? 1 : 0); // '\t'
          }
          current += 1; // '\n' separator
          return false;
        }

        if (walkCells(block.header.cells)) return;
        block.rows.any((row) => walkCells(row.cells));
      case MD$Code() || MD$Divider() || MD$Spacer():
        break;
    }
  }

  ChatInlineHit? _inlineHitForSpan(
    int messageId,
    MD$Span span, {
    Path? contourPath,
    Offset? touchOrigin,
  }) {
    final style = span.style;
    // The engine's hidden-tap rule, on the viewport's hit path too: a tap on
    // anything inside a hidden spoiler reveals the message and activates
    // nothing, so no hit is reported until it is revealed.
    if (style.contains(MD$Style.spoiler) && !spoilers.isRevealed(messageId)) {
      return null;
    }
    final extra = span.extra;
    // Each branch reads a style bit, never the URL: a mention is not a link
    // and an image is not a link.
    if (style.contains(MD$Style.image)) {
      return switch (extra?['src'] ?? extra?['url']) {
        final String target => ChatInlineHit.embed(
          messageId: messageId,
          target: target,
          alt: span.text,
          contourPath: contourPath,
          touchOrigin: touchOrigin,
        ),
        _ => null,
      };
    }
    if (style.contains(MD$Style.mention)) {
      final name = extra?['name'];
      if (name is! String) return null;
      switch (extra?['scheme']) {
        case 'mention':
          return switch (extra?['id']) {
            final String id => ChatInlineHit.resolvedMention(
              messageId: messageId,
              id: id,
              name: name,
              contourPath: contourPath,
              touchOrigin: touchOrigin,
            ),
            _ => null,
          };
        case 'username':
          return ChatInlineHit.usernameMention(
            messageId: messageId,
            name: name,
            contourPath: contourPath,
            touchOrigin: touchOrigin,
          );
        case 'hashtag':
          return ChatInlineHit.hashtag(
            messageId: messageId,
            tag: name,
            contourPath: contourPath,
            touchOrigin: touchOrigin,
          );
      }
      return null;
    }
    if (style.contains(MD$Style.link) || extra?['url'] != null) {
      final url =
          extra?['url'] as String? ?? extra?['href'] as String? ?? span.text;
      final title = extra?['alt'] as String? ?? span.text;
      return ChatInlineHit.link(
        messageId: messageId,
        title: title,
        url: url,
        contourPath: contourPath,
        touchOrigin: touchOrigin,
      );
    }
    if (style.contains(MD$Style.monospace)) {
      return ChatInlineHit.code(
        messageId: messageId,
        code: span.text,
        contourPath: contourPath,
        touchOrigin: touchOrigin,
      );
    }
    return null;
  }

  /// Inserts or updates the markdown body for [messageId].
  ///
  /// Returns an ownership [Object] token. Pass that token back on later
  /// [putBody] updates and to [removeBody]. Several mounts may share one
  /// [messageId] concurrently during state transitions; each holds its own token
  /// and model. Only the last [removeBody] drops the registry entry.
  ///
  /// [order] is the reading-order key when the document is armed.
  /// Silent after [dispose].
  Object? putBody(int messageId, Markdown model, {int? order, Object? token}) {
    if (_disposed) return null;
    final existing = _bodies[messageId];
    final assigned = order ?? existing?.order ?? _bodies.length;

    if (token != null &&
        existing != null &&
        existing.models.containsKey(token)) {
      if (identical(existing.models[token], model) &&
          existing.order == assigned &&
          identical(existing.model, model)) {
        return token;
      }
      existing
        ..order = assigned
        ..models.remove(token)
        ..models[token] = model;
      if (_active && _subjectId == messageId) {
        _syncArmedDocument();
      }
      return token;
    }

    final next = Object();
    if (existing != null) {
      existing
        ..order = assigned
        ..models[next] = model;
    } else {
      _bodies[messageId] = _BodyEntry(
        order: assigned,
        models: LinkedHashMap<Object, Markdown>.fromEntries([
          MapEntry(next, model),
        ]),
      );
    }
    if (_active && _subjectId == messageId) {
      _syncArmedDocument();
    }
    return next;
  }

  /// Removes a previously registered body.
  ///
  /// When [token] is non-null, drops only that owner. Omit [token] to
  /// force-remove every owner. When [messageId] is the active subject and
  /// the entry is fully removed, disarms text selection.
  ///
  /// Returns whether text selection was cleared as a result.
  bool removeBody(int messageId, {Object? token}) {
    if (_disposed) return false;
    final entry = _bodies[messageId];
    if (entry == null) return false;
    if (token != null) {
      if (entry.models.remove(token) == null) return false;
      if (entry.models.isNotEmpty) {
        if (_active && _subjectId == messageId) {
          _syncArmedDocument();
        }
        return false;
      }
    }
    var cleared = false;
    if (_active && _subjectId == messageId) {
      disarm();
      cleared = true;
    }
    _bodies.remove(messageId);
    _bodyPaintBoxes.remove(messageId);
    _messageSurfaceBoxes.remove(messageId);
    _messageSurfaceShapes.remove(messageId);
    return cleared;
  }

  /// Registers a body of [messageId] that paints no text, returning the token
  /// to pass to [removeNonTextBody]. Several mounts of one message may
  /// overlap (a morph); the last one answers. Silent after [dispose].
  Object? putNonTextBody(int messageId, ChatNonTextBody body) {
    if (_disposed) return null;
    final token = Object();
    (_nonTextBodies[messageId] ??=
            LinkedHashMap<Object, ChatNonTextBody>.identity())[token] =
        body;
    return token;
  }

  /// The non-text body of [messageId] that answers (the last mounted), or
  /// null.
  ChatNonTextBody? nonTextBodyOf(int messageId) =>
      _disposed ? null : _nonTextBodies[messageId]?.values.last;

  /// Removes the body registered under [token].
  void removeNonTextBody(int messageId, {required Object? token}) {
    final owners = _nonTextBodies[messageId];
    if (owners == null) return;
    owners.remove(token);
    if (owners.isEmpty) _nonTextBodies.remove(messageId);
  }

  /// Arms [messageId] as the sole document. Returns `false` when disposed
  /// or no body is registered. Pre-arm failures leave prior state unchanged.
  ///
  /// Clears any existing markdown range so a following programmatic word /
  /// select-all commit starts clean.
  bool arm(int messageId) {
    if (_disposed) return false;
    final entry = _bodies[messageId];
    if (entry == null) return false;
    markdownSelection.clear();
    _subjectId = messageId;
    _active = true;
    _syncArmedDocument();
    return true;
  }

  /// Adopts [messageId] as the **text selection subject** without clearing an
  /// existing markdown range.
  ///
  /// Used when the per-body selection scope creates a non-collapsed range and
  /// the facade must claim that subject (ADR 015). Collapses the document
  /// registry to [messageId] only. Returns `false` when disposed or no body
  /// is registered.
  bool adopt(int messageId) {
    if (_disposed) return false;
    final entry = _bodies[messageId];
    if (entry == null) return false;
    _subjectId = messageId;
    _active = true;
    _syncArmedDocument();
    return true;
  }

  /// Clears markdown text selection and disarms every document.
  ///
  /// Silent when already inactive with no range. Returns whether state
  /// changed.
  bool disarm() {
    if (_disposed) return false;
    if (!_active && markdownSelection.selection == null) return false;
    _active = false;
    _subjectId = null;
    markdownSelection
      ..clear()
      ..setDocuments(const <MarkdownDocumentRef>[]);
    return true;
  }

  /// Selects the entire armed subject body. Returns `false` when the
  /// markdown range is missing or collapsed.
  ///
  /// Re-syncs the markdown document registry to the armed subject first.
  /// Sibling body mounts share [markdownSelection] and call `putDocument` on
  /// attach; without this prune, [MarkdownSelectionController.selectAll]
  /// spans every registered document and the facade then collapses the
  /// cross-message range.
  bool selectAllSubject() {
    if (_disposed || !_active) return false;
    pruneToArmedSubject();
    markdownSelection.selectAll();
    return switch (markdownSelection.selection) {
      final sel? when !sel.isCollapsed => true,
      _ => false,
    };
  }

  /// Selects the word at [globalOffset] on the armed subject.
  ///
  /// Returns the resulting [MarkdownSelection], or `null` when disposed,
  /// inactive, or word selection missed.
  MarkdownSelection? selectWordAtGlobal(Offset globalOffset) {
    if (_disposed || !_active) return null;
    return markdownSelection.selectWordAtGlobal(globalOffset);
  }

  /// Plain text of the current range, or empty when none.
  String getText() {
    if (_disposed || !_active) return '';
    return markdownSelection.getText();
  }

  void _syncArmedDocument() {
    final id = _subjectId;
    if (!_active || id == null) {
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

  /// Collapses the markdown document registry to the armed subject when sibling
  /// mounts have re-expanded it via `putDocument`.
  ///
  /// Returns `true` when a sync ran (caller should let the resulting
  /// [markdownSelection] notify finish the work). No-op when inactive,
  /// disposed, or already subject-only.
  bool pruneToArmedSubject() {
    if (_disposed || !_active) return false;
    final id = _subjectId;
    if (id == null) return false;
    final docs = markdownSelection.documents;
    if (docs.length == 1 && docs.first.id == id) return false;
    _syncArmedDocument();
    return true;
  }

  /// Clears listeners on the markdown model and, when created here, disposes
  /// it. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _subjectId = null;
    _bodies.clear();
    _nonTextBodies.clear();
    _bodyPaintBoxes.clear();
    _messageSurfaceBoxes.clear();
    _messageSurfaceShapes.clear();
    markdownSelection
      ..clear()
      ..setDocuments(const <MarkdownDocumentRef>[]);
    if (_disposeMarkdown) {
      markdownSelection.dispose();
    }
    if (_disposeSpoilers) {
      spoilers.dispose();
    }
  }
}

final class _BodyEntry {
  _BodyEntry({required this.order, required this.models});

  int order;

  /// Owner token → model. Insertion order: [model] is the last entry’s value.
  final LinkedHashMap<Object, Markdown> models;

  Markdown get model => models.values.last;
}

typedef _SpanHitInfo = ({MD$Span span, int start, int end});

/// A span of a block with its rendered-text offsets; `isLast` marks the span
/// that owns the offset at its own end (the caret after the last character).
typedef _SpanRun = ({MD$Span span, int start, int end, bool isLast});
