import 'dart:collection';

import 'package:chatscrollview/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
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
    super.update(newWidget); // -> updateRenderObject (dataSource/controller/...)
    // The builder is not handed to the render object; if it changed, force a
    // layout so every active child is re-inflated through buildChild.
    if (!identical(old.messageBuilder, newWidget.messageBuilder)) {
      renderObject.markNeedsLayout();
    }
  }

  /// Inflate the [RepaintBoundary]-wrapped widget for message [id].
  Widget _build(int id) {
    final ds = _widget.dataSource;
    return RepaintBoundary(
      key: ValueKey<int>(id),
      child: _widget.messageBuilder(this, id, ds.getMessage(id), ds.statusOf(id)),
    );
  }

  // --- ChatChildManager (driven by RenderChatScrollView.performLayout) ------

  @override
  RenderBox? buildChild(int id) {
    RenderBox? result;
    owner!.buildScope(this, () {
      final updated = updateChild(_children[id], _build(id), id);
      if (updated != null) {
        _children[id] = updated;
        result = updated.renderObject as RenderBox?;
      } else {
        _children.remove(id);
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
    _children.remove(child.slot as int);
    super.forgetChild(child);
  }
}
