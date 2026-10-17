import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// The docked layout is drawn on the flat path: solid fills and token colours,
// no glass. The chat area (a stand-in for the host's viewport) gives up the
// published inline-end width, so the section never covers it; the layout is
// drawn left-to-right and right-to-left, where the section sits on the
// opposite edge. flutter_test renders text with the Ahem font, so glyph shapes
// do not depend on the host platform.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed: if edge anti-aliasing differs
// there, regenerate on the pinned platform or add a tolerance comparator, and
// record it here.
void main() {
  // Goldens sit next to this file, also when test/unit_test.dart runs it.
  setUpAll(
    () => goldenFileComparator = LocalFileComparator(
      Uri.file('test/goldens/docked_golden_test.dart'),
    ),
  );
  const size = Size(900, 520);

  for (final direction in TextDirection.values) {
    final name = 'docked_${direction.name}';
    testWidgets('docked layout, $name', (tester) async {
      final shell = PanelShellController(
        pages: [
          FakePanelPage(
            'emoji',
            search: true,
            color: const Color(0xFFE8F0F8),
          ).page,
          FakePanelPage('stickers').page,
        ],
        preferences: FakePreferenceStore(),
      );
      final strategy = DockedStrategy(
        style: const DockedStyle(width: 340, separator: Color(0xFFB8C2CC)),
      );
      final controller = PanelPresentationController(
        shell: shell,
        policy: const PanelPresentationPolicy$Desktop(),
        strategies: [strategy],
        window: PanelWindow(width: size.width, height: size.height),
        dockPreferred: true,
      );
      addTearDown(() {
        controller.dispose();
        shell.dispose();
        strategy.dispose();
      });
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        PanelShellTestScope(
          textDirection: direction,
          size: size,
          speed: ChromeMotionSpeed.instant,
          child: RepaintBoundary(
            key: const ValueKey('stage'),
            child: _Stage(controller: controller),
          ),
        ),
      );
      controller.show();
      await tester.pump();
      await tester.pump();
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(controller.state.value.kind, const Docked());

      await expectLater(
        find.byKey(const ValueKey('stage')),
        matchesGoldenFile('$name.png'),
      );
    });
  }
}

class _Stage extends StatefulWidget {
  const _Stage({required this.controller});

  final PanelPresentationController controller;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  @override
  void initState() {
    super.initState();
    widget.controller.occupancy.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.occupancy.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: ColoredBox(color: Color(0xFFFFFFFF))),
      Positioned.fill(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            end: widget.controller.occupancy.value.inlineEnd,
          ),
          child: const ColoredBox(
            color: Color(0xFFDDE6EE),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: SizedBox(
                width: 260,
                height: 48,
                child: ColoredBox(color: Color(0xFFB4C4D4)),
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: PanelPresentationView(controller: widget.controller),
      ),
    ],
  );
}
