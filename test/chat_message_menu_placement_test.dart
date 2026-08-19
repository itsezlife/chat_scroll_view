import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_placement.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement Y follows the tap for a short menu', () {
    final placement = computeChatMessageMenuPlacement(
      screenSize: const Size(400, 800),
      keyboardHeight: 0,
      messageRect: const Rect.fromLTWH(100, 200, 180, 40),
      menuSize: const Size(200, 160),
      tapGlobal: const Offset(250, 210),
    );

    expect(placement.menuOrigin.dy, 210);
    // Outer stack sits on the leading inset; the action card is inset
    // further by the reactions overhang (host layout), not by X here.
    expect(placement.menuOrigin.dx, kChatMessageMenuEdgeInset);
  });

  test('placement keeps the menu above the keyboard inset', () {
    final placement = computeChatMessageMenuPlacement(
      screenSize: const Size(400, 800),
      keyboardHeight: 300,
      messageRect: const Rect.fromLTWH(100, 500, 180, 40),
      menuSize: const Size(200, 250),
      tapGlobal: const Offset(200, 520),
    );

    expect(placement.menuOrigin.dx, kChatMessageMenuEdgeInset);
    expect(placement.menuOrigin.dy + 250, lessThanOrEqualTo(800 - 300));
  });

  test('placement stays above system nav safe padding', () {
    final placement = computeChatMessageMenuPlacement(
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

  test('X is independent of tap X and of outgoing vs incoming', () {
    const size = Size(384, 832);
    const rect = Rect.fromLTWH(0, -115, 384, 699);
    const menu = Size(252, 345);
    const pad = EdgeInsets.only(top: 34, bottom: 48);

    Offset originAt(double tapX) => computeChatMessageMenuPlacement(
      screenSize: size,
      keyboardHeight: 0,
      messageRect: rect,
      menuSize: menu,
      tapGlobal: Offset(tapX, 314),
      safePadding: pad,
    ).menuOrigin;

    expect(originAt(51.6).dx, originAt(308.3).dx);
    expect(originAt(51.6).dx, kChatMessageMenuEdgeInset);
    expect(
      originAt(308.3).dx,
      isNot(384 - kChatMessageMenuEdgeInset - 252),
    );
  });
}
