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
    // The default column: a card 200 wide, with the strip's overhangs (24
    // before, 48 after) beside it when there is a strip.
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
          menuSize: Size(hasReactions ? card + 72 : card, 160),
          tapGlobal: Offset(tapX, 230),
          safePadding: safePadding,
          hasReactions: hasReactions,
        ).menuOrigin.dx +
        (hasReactions ? 24 : 0);

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

  group('a popup is placed as a desktop pointer menu', () {
    ChatMessageMenuPlacement at(Offset pointer, {double keyboard = 0}) =>
        ChatMessageMenuPlacement.compute(
          screenSize: const Size(400, 800),
          keyboardHeight: keyboard,
          messageRect: const Rect.fromLTWH(0, 200, 400, 40),
          menuSize: const Size(200, 160),
          tapGlobal: pointer,
          presentation: ChatMessageMenuPresentation.popup,
        );

    test('below and right of the pointer, 5 from it, growing from its top '
        'left corner', () {
      final placement = at(const Offset(120, 210));
      expect(placement.menuOrigin, const Offset(125, 210));
      expect(placement.origin, Alignment.topLeft);
    });

    test('left of the pointer when there is no room right, from its top '
        'right corner', () {
      final placement = at(const Offset(390, 210));
      expect(placement.menuOrigin, const Offset(390 - 5 - 200, 210));
      expect(placement.origin, Alignment.topRight);
    });

    test('above the pointer when there is no room below, its bottom at the '
        'pointer, from its bottom corner', () {
      final placement = at(const Offset(120, 700));
      expect(placement.menuOrigin, const Offset(125, 700 - 160));
      expect(placement.origin, Alignment.bottomLeft);
      expect(placement.fitsAbove, isTrue);
      expect(at(const Offset(390, 700)).origin, Alignment.bottomRight);
    });

    test('above the keyboard', () {
      final placement = at(const Offset(120, 500), keyboard: 300);
      expect(placement.menuOrigin.dy, 500 - 160);
    });

    test('inside the screen when it fits neither way', () {
      final placement = at(const Offset(120, 100), keyboard: 650);
      expect(placement.menuOrigin.dy, 0);
    });
  });
}
