import 'package:bulletins/bulletins.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  testWidgets('a link is drawn in the link colour and runs its tap', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        BulletinMessage(
          message: 'See More',
          links: [BulletinLink(start: 4, end: 8, onTap: () => opened++)],
          linkColor: const Color(0xFF4DB8FF),
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
    final text = tester.widget<RichText>(find.byType(RichText));
    final spans = <TextSpan>[];
    text.text.visitChildren((span) {
      if (span case TextSpan(text: _?)) spans.add(span);
      return true;
    });
    expect(spans.map((s) => s.text), ['See ', 'More']);
    expect(spans.last.style?.color, const Color(0xFF4DB8FF));
    // The test font draws every glyph 10 px wide at size 10.
    await tester.tapAt(const Offset(65, 5));
    expect(opened, 1);
    await tester.tapAt(const Offset(5, 5));
    expect(opened, 1);
  });

  testWidgets('a prefix comes first in the same block', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const BulletinMessage(
          message: 'body',
          prefix: TextSpan(text: 'Title\n'),
          linkColor: Color(0xFF000000),
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
    expect(
      tester.widget<RichText>(find.byType(RichText)).text.toPlainText(),
      'Title\nbody',
    );
  });
}
