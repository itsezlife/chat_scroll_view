import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without a dispatcher the host back reaches the callback', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      OverlayBackButtonListener(
        onBackButtonPressed: () async {
          presses++;
          return true;
        },
        child: const SizedBox(),
      ),
    );

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    expect(presses, 1);
  });

  testWidgets('after unmount the host back is no longer handled', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      OverlayBackButtonListener(
        onBackButtonPressed: () async {
          presses++;
          return true;
        },
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    await tester.binding.handlePopRoute();
    expect(presses, 0);
  });

  testWidgets('with a dispatcher the child dispatcher takes the back', (
    tester,
  ) async {
    final root = RootBackButtonDispatcher()..addCallback(() async => false);
    var presses = 0;
    await tester.pumpWidget(
      OverlayBackButtonListener(
        parentDispatcher: root,
        onBackButtonPressed: () async {
          presses++;
          return true;
        },
        child: const SizedBox(),
      ),
    );

    final handled = await root.invokeCallback(Future<bool>.value(false));
    expect(presses, 1);
    expect(handled, isTrue);
  });
}
