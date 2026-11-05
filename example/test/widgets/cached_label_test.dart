import 'package:chat_scroll_view_example/src/common/widgets/cached_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  const style = TextStyle(fontSize: 11, height: 1);

  testWidgets('a label is as large as the same Text', (tester) async {
    await tester.pumpWidget(_host(const Text('09:05', style: style)));
    final text = tester.getSize(find.text('09:05'));

    await tester.pumpWidget(_host(const CachedLabel('09:05', style: style)));
    expect(tester.getSize(find.byType(CachedLabel)), text);
  });

  testWidgets('an icon label takes the icon box', (tester) async {
    await tester.pumpWidget(_host(const Icon(Icons.done_all, size: 14)));
    final icon = tester.getSize(find.byType(Icon));

    await tester.pumpWidget(_host(CachedLabel.icon(Icons.done_all, size: 14)));
    expect(tester.getSize(find.byType(SizedBox).last), icon);
  });

  testWidgets('a label is announced; an icon label is not', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CachedLabel('09:05', style: style),
            CachedLabel.icon(Icons.done_all, size: 14),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('09:05'), findsOneWidget);
    expect(
      find.bySemanticsLabel(String.fromCharCode(Icons.done_all.codePoint)),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('a new text relays the label out', (tester) async {
    await tester.pumpWidget(_host(const CachedLabel('9:05', style: style)));
    final narrow = tester.getSize(find.byType(CachedLabel));

    await tester.pumpWidget(_host(const CachedLabel('19:05', style: style)));
    expect(
      tester.getSize(find.byType(CachedLabel)).width,
      greaterThan(narrow.width),
    );
  });
}
