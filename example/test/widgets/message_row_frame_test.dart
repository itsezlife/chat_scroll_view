import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/message_row_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = ChatMessageThemeData.fallback;
const _last = MessageRunLayout(
  isFirstInSenderRun: true,
  isLastInSenderRun: true,
);

Widget _row({
  bool outgoing = false,
  TextDirection direction = TextDirection.ltr,
  VoidCallback? onAvatarTap,
  VoidCallback? onRowLongPress,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        child: GestureDetector(
          onLongPress: onRowLongPress,
          child: MessageRowFrame(
            theme: _theme,
            outgoing: outgoing,
            runLayout: _last,
            bubble: const ColoredBox(
              key: Key('bubble'),
              color: Color(0xFF2A2A2C),
              child: SizedBox(width: 120, height: 48),
            ),
            avatar: outgoing
                ? null
                : MessageAvatar(
                    sender: 'alice',
                    size: _theme.avatarSize,
                    color: const Color(0xFF42A5F5),
                    onTap: onAvatarTap,
                  ),
          ),
        ),
      ),
    ),
  ),
);

Rect _bubble(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('bubble')));
Rect _avatar(WidgetTester tester) => tester.getRect(find.byType(MessageAvatar));

void main() {
  testWidgets('an incoming bubble sits beside the avatar, bottoms aligned', (
    tester,
  ) async {
    await tester.pumpWidget(_row());
    final avatar = _avatar(tester);
    final bubble = _bubble(tester);
    expect(bubble.left - avatar.right, _theme.avatarGap);
    expect(bubble.bottom, avatar.bottom);
  });

  testWidgets('right to left mirrors the avatar and the bubble', (
    tester,
  ) async {
    await tester.pumpWidget(_row(direction: TextDirection.rtl));
    final avatar = _avatar(tester);
    final bubble = _bubble(tester);
    expect(avatar.left - bubble.right, _theme.avatarGap);
    expect(avatar.left, greaterThan(bubble.left));
  });

  testWidgets('an outgoing bubble sits at the column end', (tester) async {
    await tester.pumpWidget(_row(outgoing: true));
    expect(find.byType(MessageAvatar), findsNothing);
    final column = _theme.columnWidth(400);
    final columnLeft = _theme
        .columnAlignment(viewportWidth: 400, outgoing: true)
        .resolve(TextDirection.ltr)
        .alongOffset(Offset(400 - column, 0))
        .dx;
    expect(_bubble(tester).right, columnLeft + column - _theme.padding.right);
  });

  testWidgets('a tap on the avatar calls it; a long press selects nothing', (
    tester,
  ) async {
    var taps = 0;
    var rowLongPresses = 0;
    await tester.pumpWidget(
      _row(onAvatarTap: () => taps++, onRowLongPress: () => rowLongPresses++),
    );
    await tester.tap(find.byType(MessageAvatar));
    expect(taps, 1);

    await tester.longPress(find.byType(MessageAvatar));
    expect(rowLongPresses, 0);
    await tester.longPress(find.byKey(const Key('bubble')));
    expect(rowLongPresses, 1);
  });

  testWidgets('the avatar announces its initial and its tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_row(onAvatarTap: () {}));
    expect(
      tester.getSemantics(find.byType(MessageAvatar)),
      matchesSemantics(
        label: 'A',
        hasTapAction: true,
        textDirection: TextDirection.ltr,
      ),
    );
    semantics.dispose();
  });
}
