import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

/// The popup under test with a toggle at the bottom end of a window, a
/// composer strip under the popup, and a manual clock.
final class PopupRig {
  factory PopupRig({
    PanelPresentationPolicy policy = const PanelPresentationPolicy$Desktop(),
    AnchoredPopupStyle style = const AnchoredPopupStyle(width: 300),
    PanelWindow window = const PanelWindow(width: 800, height: 700),
  }) {
    final clock = ManualPanelClock();
    final composerFocus = FocusNode(debugLabel: 'composer');
    final elsewhereFocus = FocusNode(debugLabel: 'elsewhere');
    final strategy = AnchoredPopupStrategy(
      style: style,
      clock: clock,
      composerFocus: composerFocus,
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
      policy: policy,
      strategies: [strategy, FakePresentationStrategy(const Docked())],
      window: window,
    );
    addTearDown(() {
      controller.dispose();
      shell.dispose();
      strategy.dispose();
      composerFocus.dispose();
      elsewhereFocus.dispose();
    });
    return PopupRig._(
      shell: shell,
      controller: controller,
      strategy: strategy,
      clock: clock,
      composerFocus: composerFocus,
      elsewhereFocus: elsewhereFocus,
    );
  }

  PopupRig._({
    required this.shell,
    required this.controller,
    required this.strategy,
    required this.clock,
    required this.composerFocus,
    required this.elsewhereFocus,
  });

  final PanelShellController shell;
  final PanelPresentationController controller;
  final AnchoredPopupStrategy strategy;
  final ManualPanelClock clock;
  final FocusNode composerFocus;
  final FocusNode elsewhereFocus;

  static const toggleKey = ValueKey('toggle');
  static const outsideKey = ValueKey('outside');
  static const exemptKey = ValueKey('exempt');

  /// The composer strip, 60 px tall, at the bottom of an 800 x 700 window.
  static const composer = Rect.fromLTWH(0, 640, 800, 60);

  /// Where the toggle sits: inside the composer, at its end.
  static const toggleRect = Rect.fromLTWH(740, 650, 40, 40);

  Future<void> pump(
    WidgetTester tester, {
    TextDirection textDirection = TextDirection.ltr,
    Size size = const Size(800, 700),
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    VoidCallback? onOutsideTap,
    Rect? composerRect,
    Rect? exemptRect,
    bool withToggle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final composerBox =
        composerRect ??
        (size.width == 800 && size.height == 700
            ? composer
            : Rect.fromLTWH(0, size.height - 60, size.width, 60));
    controller.anchor(composerBox);
    await tester.pumpWidget(
      PanelShellTestScope(
        size: size,
        textDirection: textDirection,
        speed: speed,
        child: Shortcuts(
          shortcuts: AnchoredPopupShortcuts.standard,
          child: AnchoredPopupActions(
            controller: controller,
            child: Stack(
              children: [
                Focus(
                  focusNode: elsewhereFocus,
                  child: const SizedBox.shrink(),
                ),
                Positioned.fill(
                  child: Focus(
                    focusNode: composerFocus,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOutsideTap,
                      child: const SizedBox.expand(key: outsideKey),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    textDirection == TextDirection.ltr ? size.width - 60 : 20,
                    size.height - 50,
                    40,
                    40,
                  ),
                  child: withToggle
                      ? AnchoredPopupToggleRegion(
                          strategy: strategy,
                          controller: controller,
                          child: const SizedBox.expand(key: toggleKey),
                        )
                      : const SizedBox.shrink(),
                ),
                if (exemptRect != null)
                  Positioned.fromRect(
                    key: const ValueKey('exempt-slot'),
                    rect: exemptRect,
                    child: AnchoredPopupExemptRegion(
                      strategy: strategy,
                      child: const SizedBox.expand(key: exemptKey),
                    ),
                  ),
                Positioned.fill(
                  key: const ValueKey('presentation-slot'),
                  child: PanelPresentationView(controller: controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> mouse(WidgetTester tester, {Offset? at}) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: at ?? const Offset(1, 1));
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }
}

/// Past the longest motion, without changing the manual clock.
Future<void> settleMotion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

bool popupIsUp(WidgetTester tester) =>
    find.byType(PanelShell).evaluate().isNotEmpty;
