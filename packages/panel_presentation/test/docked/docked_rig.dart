import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

/// A host window with a chat area that gives up the controller's inline-end
/// occupancy, a composer focus node, and the docked and popup strategies.
final class DockedRig {
  factory DockedRig({
    DockedStyle style = const DockedStyle(width: 320),
    PanelWindow window = const PanelWindow(width: 1000, height: 600),
    bool dockPreferred = false,
    PreferenceStore? preferences,
    DockWidthStore? dockWidths,
  }) {
    final composerFocus = FocusNode(debugLabel: 'composer');
    final docked = DockedStrategy(style: style, composerFocus: composerFocus);
    final popup = AnchoredPopupStrategy(
      style: const AnchoredPopupStyle(width: 300),
      clock: ManualPanelClock(),
    );
    final shell = PanelShellController(
      pages: [
        FakePanelPage('emoji', search: true).page,
        FakePanelPage('stickers').page,
      ],
      preferences: FakePreferenceStore(),
    );
    final controller = PanelPresentationController(
      shell: shell,
      policy: const PanelPresentationPolicy$Desktop(),
      strategies: [popup, docked],
      window: window,
      dockPreferred: dockPreferred,
      preferences: preferences,
      dockWidths: dockWidths,
    );
    addTearDown(() {
      controller.dispose();
      shell.dispose();
      docked.dispose();
      popup.dispose();
      composerFocus.dispose();
    });
    return DockedRig._(
      controller: controller,
      shell: shell,
      docked: docked,
      composerFocus: composerFocus,
    );
  }

  DockedRig._({
    required this.controller,
    required this.shell,
    required this.docked,
    required this.composerFocus,
  });

  final PanelPresentationController controller;
  final PanelShellController shell;
  final DockedStrategy docked;
  final FocusNode composerFocus;

  static const chatKey = ValueKey('chat');

  Future<void> pump(
    WidgetTester tester, {
    TextDirection textDirection = TextDirection.ltr,
    Size size = const Size(1000, 600),
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: size,
        textDirection: textDirection,
        speed: speed,
        child: _Host(controller: controller, composerFocus: composerFocus),
      ),
    );
  }
}

/// Lays the chat out in what the docked section leaves, as a host does.
class _Host extends StatefulWidget {
  const _Host({required this.controller, required this.composerFocus});

  final PanelPresentationController controller;
  final FocusNode composerFocus;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
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
      Positioned.fill(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            end: widget.controller.occupancy.value.inlineEnd,
          ),
          child: Focus(
            focusNode: widget.composerFocus,
            child: const ColoredBox(
              key: DockedRig.chatKey,
              color: Color(0xFFF0F0F0),
              child: SizedBox.expand(),
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

/// Past the longest motion.
Future<void> settleDock(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}
