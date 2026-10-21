import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The labels of the semantics tree itself.
///
/// `find.bySemanticsLabel` reads the widgets' own nodes, which still exist for
/// a subtree the tree no longer visits (a page that is out of sight); this reads
/// what a screen reader is given. Needs `tester.ensureSemantics()`.
Set<String> spokenLabels(WidgetTester tester) {
  final labels = <String>{};
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}
