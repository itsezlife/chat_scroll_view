import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = LiquidGlassStyle(
  fill: Color(0xD9202020),
  strokeTop: Color(0x28FFFFFF),
  strokeBottom: Color(0x14FFFFFF),
  shadowColor: Color(0x00000000),
  enableLiquid: false,
);

const _glassKey = ValueKey('glass');

Widget _glass() => const Center(
  child: SizedBox(
    width: 200,
    height: 44,
    child: LiquidGlass(key: _glassKey, style: _style, child: SizedBox.expand()),
  ),
);

Route<void> _route(Widget child) => PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 200),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, animation, secondaryAnimation) => child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(1, 0), end: Offset.zero),
        ),
        child: child,
      ),
);

bool _filtersBackdrop() => find
    .descendant(
      of: find.byKey(_glassKey),
      matching: find.byType(BackdropFilter),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  group('LiquidGlass', () {
    late GlobalKey<NavigatorState> navigator;

    setUp(() => navigator = GlobalKey<NavigatorState>());

    Future<void> pumpHome(WidgetTester tester, Widget home) =>
        tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: home));

    testWidgets('filters the backdrop outside a moving route', (tester) async {
      await pumpHome(tester, _glass());

      expect(_filtersBackdrop(), isTrue);
    });

    testWidgets(
      'paints its fill flat while its route is pushed, then filters',
      (tester) async {
        await pumpHome(tester, const SizedBox());
        navigator.currentState!.push(_route(_glass())).ignore();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(_filtersBackdrop(), isFalse);

        await tester.pumpAndSettle();
        expect(_filtersBackdrop(), isTrue);
      },
    );

    testWidgets('paints its fill flat while its route is popped', (
      tester,
    ) async {
      await pumpHome(tester, const SizedBox());
      navigator.currentState!.push(_route(_glass())).ignore();
      await tester.pumpAndSettle();

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_filtersBackdrop(), isFalse);
    });

    testWidgets('paints its fill flat while a route above it transitions', (
      tester,
    ) async {
      await pumpHome(tester, _glass());
      navigator.currentState!
          .push(
            MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
          )
          .ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_filtersBackdrop(), isFalse);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_filtersBackdrop(), isTrue);
    });
  });
}
