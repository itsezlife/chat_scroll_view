import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A surface of two parts with a gap between them, as a message with a header
// panel above a bare body: 100 x 80 box, the header the top 20, the body from
// 40 down.
const _header = ChatMessageSurfacePart(
  rect: Rect.fromLTWH(0, 0, 60, 20),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
);
const _body = ChatMessageSurfacePart(rect: Rect.fromLTWH(10, 40, 80, 40));
const _parts = ChatMessageSurfaceParts(<ChatMessageSurfacePart>[_header, _body]);

void main() {
  group('ChatMessageSurfaceParts', () {
    test('the outer path is the union of the parts, from the box origin', () {
      final path = _parts.getOuterPath(const Rect.fromLTWH(200, 300, 100, 80));

      // Header, body (both moved by the box origin).
      expect(path.contains(const Offset(230, 310)), isTrue);
      expect(path.contains(const Offset(250, 340)), isTrue);
      // The gap between them and the box corner no part covers.
      expect(path.contains(const Offset(230, 330)), isFalse);
      expect(path.contains(const Offset(295, 305)), isFalse);
      // The header's rounded corner is cut, the body's square one is not.
      expect(path.contains(const Offset(200.5, 300.5)), isFalse);
      expect(path.contains(const Offset(210.5, 340.5)), isTrue);
    });

    test('a directional part shape resolves against the text direction', () {
      const parts = ChatMessageSurfaceParts(<ChatMessageSurfacePart>[
        ChatMessageSurfacePart(
          rect: Rect.fromLTWH(0, 0, 100, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadiusDirectional.only(topStart: Radius.circular(20))),
        ),
      ]);
      const box = Rect.fromLTWH(0, 0, 100, 40);

      final ltr = parts.getOuterPath(box, textDirection: TextDirection.ltr);
      final rtl = parts.getOuterPath(box, textDirection: TextDirection.rtl);

      expect(ltr.contains(const Offset(1, 1)), isFalse);
      expect(ltr.contains(const Offset(99, 1)), isTrue);
      expect(rtl.contains(const Offset(1, 1)), isTrue);
      expect(rtl.contains(const Offset(99, 1)), isFalse);
    });

    test('has value equality, so an unchanged hole does not repaint', () {
      const same = ChatMessageSurfaceParts(<ChatMessageSurfacePart>[_header, _body]);
      const other = ChatMessageSurfaceParts(<ChatMessageSurfacePart>[_body]);

      expect(_parts, same);
      expect(_parts.hashCode, same.hashCode);
      expect(_parts, isNot(other));
    });

    test('scale scales every part', () {
      final scaled = _parts.scale(2) as ChatMessageSurfaceParts;

      expect(scaled.parts.last.rect, const Rect.fromLTWH(20, 80, 160, 80));
    });

    test('has no border insets and paints nothing', () {
      expect(_parts.dimensions, EdgeInsets.zero);
    });
  });

  group('scrim hole of a surface made of parts', () {
    testWidgets('dims the gap between the parts and the box corners', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ChatMessageMenu.show(
                  context: context,
                  messageRect: const Rect.fromLTWH(0, 100, 400, 100),
                  surfaceRect: const Rect.fromLTWH(200, 110, 100, 80),
                  surfaceShape: _parts,
                  items: const <ChatMessageMenuItem>[
                    ChatMessageMenuItem(id: 'a', label: 'A', icon: Icons.edit_outlined),
                  ],
                  tapGlobal: const Offset(250, 150),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byType(ChatMessageMenuScrim),
        paints..path(
          // Dimmed: the gap, the box corner, outside the box.
          includes: const <Offset>[Offset(230, 140), Offset(295, 115), Offset(10, 10)],
          // Undimmed: inside the header and inside the body.
          excludes: const <Offset>[Offset(230, 120), Offset(250, 170)],
        ),
      );
    });
  });
}
