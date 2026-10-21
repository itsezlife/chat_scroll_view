import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// The semantic nodes the viewport hands the platform for its cells, in reading
/// order: the children of the one container node under the viewport's own.
/// Needs `tester.ensureSemantics()`.
List<SemanticsNode> viewportNodes(WidgetTester tester) {
  final root = tester.getSemantics(find.byType(PanelCatalogViewport));
  final out = <SemanticsNode>[];
  root.visitChildren((container) {
    container.visitChildren((child) {
      out.add(child);
      return true;
    });
    return true;
  });
  return out..sort((a, b) => a.sortKey!.compareTo(b.sortKey!));
}

/// Where [node] (one of [viewportNodes]) sits in the viewport, which is the
/// content rect it holds moved by the scroll transform of its container.
Rect viewportRectOf(SemanticsNode node) {
  final scroll = node.parent!.transform;
  return scroll == null
      ? node.rect
      : MatrixUtils.transformRect(scroll, node.rect);
}

/// The one node with [label] among [viewportNodes].
SemanticsNode viewportNodeLabelled(WidgetTester tester, String label) =>
    viewportNodes(tester).singleWhere((n) => n.label == label);

/// Performs [action] on [node] the way the platform would.
void performSemanticsAction(
  WidgetTester tester,
  SemanticsNode node,
  SemanticsAction action,
) => tester.binding.platformDispatcher.onSemanticsActionEvent!(
  SemanticsActionEvent(
    type: action,
    viewId: tester.view.viewId,
    nodeId: node.id,
  ),
);
