import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_placement.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_presentation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement Y follows the tap for a short menu', () {
    final placement = ChatMessageMenuPlacement.compute(
      screenSize: const Size(400, 800),
      keyboardHeight: 0,
      messageRect: const Rect.fromLTWH(100, 200, 180, 40),
      menuSize: const Size(200, 160),
      tapGlobal: const Offset(250, 210),
    );

    expect(placement.menuOrigin.dy, 210);
  });

  test('placement keeps the menu above the keyboard inset', () {
    final placement = ChatMessageMenuPlacement.compute(
      screenSize: const Size(400, 800),
      keyboardHeight: 300,
      messageRect: const Rect.fromLTWH(100, 500, 180, 40),
      menuSize: const Size(200, 250),
      tapGlobal: const Offset(200, 520),
    );

    expect(placement.menuOrigin.dy + 250, lessThanOrEqualTo(800 - 300));
  });

  test('placement stays above system nav safe padding', () {
    final placement = ChatMessageMenuPlacement.compute(
      screenSize: const Size(400, 800),
      keyboardHeight: 0,
      messageRect: const Rect.fromLTWH(100, 700, 180, 40),
      menuSize: const Size(200, 280),
      tapGlobal: const Offset(200, 720),
      safePadding: const EdgeInsets.only(bottom: 48, top: 24),
    );

    expect(placement.menuOrigin.dy + 280, lessThanOrEqualTo(800 - 48));
    expect(placement.menuOrigin.dy, greaterThanOrEqualTo(24 + 24));
  });

  group('a sheet hangs left of the press', () {
    // The default column: a card 200 wide with the strip's overhangs (24
    // before, 48 after) beside it.
    const menu = Size(272, 160);
    const card = 200.0;

    double cardLeftFor(
      double tapX, {
      required bool hasReactions,
      double screenWidth = 400,
      EdgeInsets safePadding = EdgeInsets.zero,
    }) =>
        ChatMessageMenuPlacement.compute(
          screenSize: Size(screenWidth, 800),
          keyboardHeight: 0,
          messageRect: const Rect.fromLTWH(0, 200, 400, 60),
          menuSize: menu,
          tapGlobal: Offset(tapX, 230),
          safePadding: safePadding,
          hasReactions: hasReactions,
        ).menuOrigin.dx +
        24;

    test('without reactions its card ends 28 left of the press', () {
      expect(cardLeftFor(300, hasReactions: false) + card, 300 - 28);
    });

    test('with reactions its card ends 64 left of the press, the strip '
        'margins beside it', () {
      expect(cardLeftFor(330, hasReactions: true) + card, 330 - 64);
    });

    test('its box stays 6 inside the screen: the card 14 from the start '
        'without reactions, 30 with them', () {
      expect(cardLeftFor(40, hasReactions: false), 14);
      expect(cardLeftFor(40, hasReactions: true), 30);
    });

    test('and 6 inside the end of a safe inset: the card 14 from it without '
        'reactions, 50 with them', () {
      const inset = EdgeInsets.only(right: 40);
      expect(
        cardLeftFor(399, hasReactions: false, safePadding: inset) + card,
        360 - 14,
      );
      expect(
        cardLeftFor(399, hasReactions: true, safePadding: inset) + card,
        360 - 50,
      );
    });

    test('inside the safe insets', () {
      expect(
        cardLeftFor(
          40,
          hasReactions: false,
          safePadding: const EdgeInsets.only(left: 30),
        ),
        44,
      );
    });
  });

  test('popup X follows the tap within edge clamps', () {
    final placement = ChatMessageMenuPlacement.compute(
      screenSize: const Size(400, 800),
      keyboardHeight: 0,
      messageRect: const Rect.fromLTWH(100, 200, 180, 40),
      menuSize: const Size(200, 160),
      tapGlobal: const Offset(120, 210),
      presentation: ChatMessageMenuPresentation.popup,
    );

    expect(placement.menuOrigin.dx, 120);
    expect(placement.menuOrigin.dy, 210);
  });

  test('popup X clamps near the trailing edge', () {
    final placement = ChatMessageMenuPlacement.compute(
      screenSize: const Size(400, 800),
      keyboardHeight: 0,
      messageRect: const Rect.fromLTWH(100, 200, 180, 40),
      menuSize: const Size(200, 160),
      tapGlobal: const Offset(390, 210),
      presentation: ChatMessageMenuPresentation.popup,
    );

    expect(
      placement.menuOrigin.dx,
      400 - 200 - ChatMessageMenuPlacement.edgeInset,
    );
  });
}
