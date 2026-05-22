import 'dart:collection';

import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/chat_selectable_message.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/widgets.dart';

/// Element for [ChatScrollView].
///
/// Owns a sparse, id-keyed set of child elements and inflates them on demand —
/// the same lazy-child machinery as `SliverMultiBoxAdaptorElement`, minus the
/// sliver protocol. [RenderChatScrollView] drives building during layout via
/// the [ChatChildManager] interface.
class ChatScrollElement extends RenderObjectElement
    implements ChatChildManager {
  ChatScrollElement(ChatScrollView super.widget);

  /// messageId -> child element, sorted so iteration is top-to-bottom.
  final SplayTreeMap<int, Element> _children = SplayTreeMap<int, Element>();

  /// Skip-rebuild cache: the message instance and status each child was last
  /// built with. When [buildChild] is asked for an id whose message instance
  /// and status are unchanged, the existing child is reused without running
  /// `updateChild` / the message widget's `build()` again.
  final Map<int, IChatMessage?> _builtMessage = <int, IChatMessage?>{};
  final Map<int, ChatMessageStatus> _builtStatus = <int, ChatMessageStatus>{};

  ChatScrollView get _widget => widget as ChatScrollView;

  @override
  RenderChatScrollView get renderObject =>
      super.renderObject as RenderChatScrollView;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.childManager = this;
  }

  @override
  void update(ChatScrollView newWidget) {
    final old = _widget;
    super.update(
      newWidget,
    ); // -> updateRenderObject (dataSource/controller/...)
    // Neither the builder nor the selection controller is handed to the render
    // object; if either changed, drop the skip-cache and force a layout so
    // every active child re-inflates with the new wrapping.
    if (!identical(old.messageBuilder, newWidget.messageBuilder) ||
        !identical(old.selectionController, newWidget.selectionController)) {
      _builtMessage.clear();
      _builtStatus.clear();
      renderObject.markNeedsLayout();
    }
  }

  /// Inflate the [RepaintBoundary]-wrapped widget for message [id].
  ///
  /// When a selection controller is wired the content is wrapped in
  /// [SelectableMessage] (checkbox gutter + row tint). The [RepaintBoundary]
  /// stays the outermost widget so each message remains its own paint /
  /// compositing layer regardless of selection.
  Widget _buildWidget(int id, IChatMessage? message, ChatMessageStatus status) {
    Widget content = _widget.messageBuilder(this, id, message, status);
    final selection = _widget.selectionController;
    if (selection != null) {
      content = SelectableMessage(
        id: id,
        controller: selection,
        child: content,
      );
    }
    return RepaintBoundary(key: ValueKey<int>(id), child: content);
  }

  // --- ChatChildManager (driven by RenderChatScrollView.performLayout) ------

  @override
  RenderBox? buildChild(int id) {
    final ds = _widget.dataSource;
    final message = ds.getMessage(id);
    final status = ds.statusOf(id);
    final existing = _children[id];

    // Fast path: the message instance and status are unchanged since this
    // child was last built — reuse it without rebuilding. Inherited-widget
    // changes (Theme, MediaQuery, ...) still rebuild the child through the
    // normal dependency mechanism, and width changes are handled by the
    // subsequent `child.layout()`, so this only skips redundant data rebuilds.
    if (existing != null &&
        _builtStatus[id] == status &&
        identical(_builtMessage[id], message)) {
      return existing.renderObject as RenderBox?;
    }

    RenderBox? result;
    owner!.buildScope(this, () {
      final updated = updateChild(
        existing,
        _buildWidget(id, message, status),
        id,
      );
      if (updated != null) {
        _children[id] = updated;
        _builtMessage[id] = message;
        _builtStatus[id] = status;
        result = updated.renderObject as RenderBox?;
      } else {
        _children.remove(id);
        _builtMessage.remove(id);
        _builtStatus.remove(id);
      }
    });
    return result;
  }

  @override
  void removeChildren(List<int> ids) {
    if (ids.isEmpty) return;
    owner!.buildScope(this, () {
      for (final id in ids) {
        final removed = updateChild(_children[id], null, id);
        assert(removed == null);
        _children.remove(id);
        _builtMessage.remove(id);
        _builtStatus.remove(id);
      }
    });
  }

  // --- RenderObjectElement plumbing -----------------------------------------

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.insertChild(child as RenderBox, slot! as int);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.removeChild(slot! as int);
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {
    assert(false, 'ChatScrollElement children never change slot');
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final child in _children.values) {
      visitor(child);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(child.slot is int);
    assert(_children.containsKey(child.slot));
    final id = child.slot! as int;
    _children.remove(id);
    _builtMessage.remove(id);
    _builtStatus.remove(id);
    super.forgetChild(child);
  }
}
