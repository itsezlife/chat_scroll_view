import 'package:flutter/foundation.dart' show UniqueKey;
import 'package:flutter/semantics.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// What the semantic nodes of the catalog need from the viewport that owns
/// them: where things are painted, and what each action does.
///
/// The viewport implements it; the nodes hold no state of their own beyond
/// their identity, so a node never outlives the viewport's idea of its cell.
abstract interface class CatalogSemanticsTarget {
  /// The hit area of [header]'s action in content coordinates.
  Rect? semanticActionBounds(CatalogHeaderSlot header);

  /// The tap of [hit], or null when the shell has no tap.
  VoidCallback? semanticTapOf(CatalogLeafHit hit);

  /// The long-press of [hit], or null when the shell has none for it.
  VoidCallback? semanticLongPressOf(CatalogLeafHit hit);

  /// The action [actionId] of section [sectionId], or null when the shell
  /// reacts to none.
  VoidCallback? semanticActionOf(String sectionId, String actionId);

  /// Moves roving focus to [hit].
  VoidCallback semanticFocusOf(CatalogLeafHit hit);

  /// Scrolls the cell [index] of [sectionId] into view (the header when
  /// [index] is null).
  VoidCallback semanticRevealOf(String sectionId, int? index);

  /// Whether the cell [index] of [sectionId] holds roving focus.
  bool semanticIsFocused(String sectionId, int index);
}

/// The semantic nodes of the visible window of the catalog.
///
/// A painted catalog has no child objects to describe, so the viewport
/// describes it itself: one node per header, header action, empty-message row
/// and leaf **in the window it is given**, and none for the rest. The window is
/// the slot range the viewport already resolves for its asset bindings (the
/// visible band plus one cell of overscan, found by binary search), so the cost
/// of an update follows the band, never the catalogue, and no node reads a
/// binding or a sprite.
///
/// Nodes are reused by cell identity (section id and index) while the cell
/// stays in the window, so a screen reader's focus does not jump when the
/// catalogue scrolls. A node outside the viewport but inside the overscan is
/// not hidden: a screen reader that moves on to it asks for it on screen, which
/// scrolls its leaf in.
///
/// ## Content space
///
/// The nodes live in **content coordinates** under one container node whose
/// transform is the scroll offset. Scrolling inside the same window moves only
/// that transform: no leaf node changes, so none is sent to the platform again.
/// (Placing each node by its viewport rect would change every node on every
/// scrolled frame.)
final class CatalogSemanticNodes {
  /// Nodes of the last assembly by cell identity; only those still in the
  /// window survive the next one.
  Map<(int, String, int), SemanticsNode> _nodes = {};

  /// The node whose transform scrolls the nodes below it.
  SemanticsNode? _container;

  /// Whether the container holds any node. An empty container is an invisible
  /// node, which the framework refuses, so it is only attached when it has
  /// children.
  var _hasNodes = false;

  static const int _header = 0;
  static const int _action = 1;
  static const int _message = 2;
  static const int _leaf = 3;

  /// Gives up the nodes. Call from `clearSemantics`.
  void clear() {
    _nodes = {};
    _container = null;
    _hasNodes = false;
  }

  /// Whether a window has been assembled, so that [scrollTo] has nodes to move.
  bool get hasWindow => _container != null;

  /// Moves the nodes already assembled to [scrollOffset], leaving every one of
  /// them as it is: the cheap answer to a scroll that does not change which
  /// slots are in the window or anything the nodes say.
  void scrollTo({
    required SemanticsNode node,
    required SemanticsConfiguration config,
    required double scrollOffset,
  }) {
    final container = _container!;
    container.transform = Matrix4.translationValues(0, -scrollOffset, 0);
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: _hasNodes ? [container] : const [],
    );
  }

  /// Fills [node] with the nodes of `slots[start]` up to, not including,
  /// `slots[end]`.
  ///
  /// [scrollOffset] turns content coordinates into the viewport's own and
  /// [width] is the viewport's.
  void assemble({
    required SemanticsNode node,
    required SemanticsConfiguration config,
    required List<CatalogLayoutSlot> slots,
    required int start,
    required int end,
    required double scrollOffset,
    required double width,
    required TextDirection textDirection,
    required CatalogSemanticsTarget target,
  }) {
    final next = <(int, String, int), SemanticsNode>{};
    final children = <SemanticsNode>[];
    var top = double.infinity;
    var bottom = double.negativeInfinity;

    void obtain(
      (int, String, int) key,
      SemanticsConfiguration configuration,
      Rect rect,
      VoidCallback showOnScreen,
    ) {
      // A band with no area (a zero extent) is a node nobody can reach, which
      // the framework refuses.
      if (rect.isEmpty) return;
      if (rect.top < top) top = rect.top;
      if (rect.bottom > bottom) bottom = rect.bottom;
      final child =
          _nodes[key] ??
          SemanticsNode(key: UniqueKey(), showOnScreen: showOnScreen);
      child
        ..updateWith(config: configuration)
        ..rect = rect;
      next[key] = child;
      children.add(child);
    }

    for (var i = start; i < end; i++) {
      final slot = slots[i];
      final order = i.toDouble();
      switch (slot) {
        case final CatalogHeaderSlot header:
          obtain(
            (_header, header.sectionId, 0),
            SemanticsConfiguration()
              ..isHeader = true
              ..label = header.title
              ..textDirection = header.textDirection
              ..sortKey = OrdinalSortKey(order),
            Rect.fromLTWH(header.left, header.top, header.width, header.height),
            target.semanticRevealOf(header.sectionId, null),
          );
          final action = header.action;
          final bounds = target.semanticActionBounds(header);
          if (action != null && bounds != null) {
            obtain(
              (_action, header.sectionId, 0),
              SemanticsConfiguration()
                ..isButton = true
                ..label = action.semanticLabel ?? action.label ?? ''
                ..textDirection = header.textDirection
                ..sortKey = OrdinalSortKey(order + 0.5)
                .._maybeTap(
                  target.semanticActionOf(header.sectionId, action.id),
                ),
              bounds,
              target.semanticRevealOf(header.sectionId, null),
            );
          }
        case final CatalogMessageSlot message:
          obtain(
            (_message, message.text, i),
            SemanticsConfiguration()
              ..label = message.text
              ..textDirection = textDirection
              ..sortKey = OrdinalSortKey(order),
            Rect.fromLTWH(
              message.left,
              message.top,
              message.width,
              message.height,
            ),
            () {},
          );
        case final CatalogLeafSlot leaf:
          final hit = leaf.hit;
          obtain(
            (_leaf, leaf.sectionId, leaf.index),
            SemanticsConfiguration()
              ..isButton = true
              ..isFocused = target.semanticIsFocused(leaf.sectionId, leaf.index)
              ..label = leaf.leaf.semanticLabel ?? ''
              ..textDirection = textDirection
              ..sortKey = OrdinalSortKey(order)
              ..onFocus = target.semanticFocusOf(hit)
              .._maybeTap(target.semanticTapOf(hit))
              .._maybeLongPress(target.semanticLongPressOf(hit)),
            Rect.fromLTWH(leaf.left, leaf.top, leaf.width, leaf.height),
            target.semanticRevealOf(leaf.sectionId, leaf.index),
          );
        case CatalogSkeletonSlot():
          // A skeleton is no content: nothing to read, nothing to activate.
          break;
      }
    }
    _nodes = next;

    // The container spans the nodes it holds, in content space, and carries the
    // scroll offset as its transform.
    final container = _container ??= SemanticsNode(key: UniqueKey());
    container
      ..updateWith(
        config: SemanticsConfiguration(),
        childrenInInversePaintOrder: children.reversed.toList(),
      )
      ..rect = children.isEmpty
          ? Rect.zero
          : Rect.fromLTRB(0, top, width, bottom)
      ..transform = Matrix4.translationValues(0, -scrollOffset, 0);
    _hasNodes = children.isNotEmpty;
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: _hasNodes ? [container] : const [],
    );
  }
}

// The setters take a callback or nothing at all: a null is an error, and an
// action that is not offered must not be in the node.
extension on SemanticsConfiguration {
  void _maybeTap(VoidCallback? callback) {
    if (callback != null) onTap = callback;
  }

  void _maybeLongPress(VoidCallback? callback) {
    if (callback != null) onLongPress = callback;
  }
}
