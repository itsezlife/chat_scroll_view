import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'clears island cutout when glass unmounts without zoneHeight change',
    (tester) async {
      final glassKey = GlobalKey();
      final islandVisible = ValueNotifier<bool>(true);
      addTearDown(islandVisible.dispose);

      await tester.pumpWidget(_FadeHarness(
        glassKey: glassKey,
        islandVisible: islandVisible,
      ));
      await tester.pump();

      final state = tester.state<ChatContentBottomFadeState>(
        find.byType(ChatContentBottomFade),
      );
      expect(state.debugCutout, isNotNull);

      islandVisible.value = false;
      await tester.pump();
      await tester.pump();

      expect(state.debugCutout, isNull);
      expect(find.byType(ChatContentBottomFade), findsOneWidget);
    },
  );

  testWidgets('restores island cutout when glass remounts via cutoutSync', (
    tester,
  ) async {
    final glassKey = GlobalKey();
    final islandVisible = ValueNotifier<bool>(true);
    addTearDown(islandVisible.dispose);

    await tester.pumpWidget(_FadeHarness(
      glassKey: glassKey,
      islandVisible: islandVisible,
    ));
    await tester.pump();

    final state = tester.state<ChatContentBottomFadeState>(
      find.byType(ChatContentBottomFade),
    );
    expect(state.debugCutout, isNotNull);

    islandVisible.value = false;
    await tester.pump();
    await tester.pump();
    expect(state.debugCutout, isNull);

    islandVisible.value = true;
    await tester.pump();
    await tester.pump();
    expect(state.debugCutout, isNotNull);
  });
}

/// Fade is **outside** [ListenableBuilder] so it does not rebuild when the
/// island unmounts — only [ChatContentBottomFade.cutoutSync] fires.
class _FadeHarness extends StatelessWidget {
  const _FadeHarness({
    required this.glassKey,
    required this.islandVisible,
  });

  final GlobalKey glassKey;
  final ValueNotifier<bool> islandVisible;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: ChatContentBottomFade(
              zoneHeight: 120,
              color: const Color(0xFF15191E),
              glassKey: glassKey,
              cutoutSync: islandVisible,
            ),
          ),
          ListenableBuilder(
            listenable: islandVisible,
            builder: (context, _) {
              if (!islandVisible.value) return const SizedBox.shrink();
              return Positioned(
                left: 24,
                right: 24,
                bottom: 16,
                height: 48,
                child: ColoredBox(key: glassKey, color: Colors.white),
              );
            },
          ),
        ],
      ),
    ),
  );
}
