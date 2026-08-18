import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets_binding.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatViewportInsets', () {
    test('topPadding is safeTop plus headerReserve', () {
      final insets = ChatViewportInsets();
      addTearDown(insets.dispose);

      expect(insets.topPadding.value, 0);

      insets.setSafeTop(20);
      insets.headerReserve.value = 52;

      expect(insets.topPadding.value, 72);
    });

    test('bottomPadding is composerHeight plus keyboard', () {
      final insets = ChatViewportInsets();
      addTearDown(insets.dispose);

      expect(insets.bottomPadding.value, 96);

      insets.setComposerHeight(120);
      insets.setKeyboard(30);

      expect(insets.keyboard.value, 30);
      expect(insets.bottomPadding.value, 150);
    });

    test('identical values do not notify', () {
      final insets = ChatViewportInsets(composerHeight: 96);
      addTearDown(insets.dispose);

      var bottomTicks = 0;
      var topTicks = 0;
      var keyboardTicks = 0;
      insets.bottomPadding.addListener(() => bottomTicks++);
      insets.topPadding.addListener(() => topTicks++);
      insets.keyboard.addListener(() => keyboardTicks++);

      insets.setComposerHeight(96);
      insets.setKeyboard(0);
      insets.setSafeTop(0);
      insets.headerReserve.value = 0;

      expect(bottomTicks, 0);
      expect(topTicks, 0);
      expect(keyboardTicks, 0);
    });

    test('dispose does not throw after updates', () {
      final insets = ChatViewportInsets();
      insets
        ..setKeyboard(12)
        ..setComposerHeight(100)
        ..setSafeTop(8);
      insets.headerReserve.value = 24;
      insets.dispose();
    });
  });

  group('ChatViewportInsetsBinding', () {
    testWidgets('writes viewPadding.top into insets', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(viewPadding: EdgeInsets.only(top: 47)),
          child: _InsetsBindingHost(),
        ),
      );

      final state = tester.state<_InsetsBindingHostState>(
        find.byType(_InsetsBindingHost),
      );
      expect(state.insets.topPadding.value, 47);
    });
  });
}

class _InsetsBindingHost extends StatefulWidget {
  const _InsetsBindingHost();

  @override
  State<_InsetsBindingHost> createState() => _InsetsBindingHostState();
}

class _InsetsBindingHostState extends State<_InsetsBindingHost>
    with ChatViewportInsetsBinding {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
